package predict

import (
	"math"
	"sort"
	"time"

	"github.com/donwb/beach/api/internal/models"
)

// Scorecard outcomes, per (ramp, peak). The asymmetry is deliberate:
// "possible" is a hedge, so an open ramp under a "possible" call costs
// nothing, while a closed ramp under a "none" call is a genuine miss.
const (
	OutcomeHit        = "hit"         // predicted likely, ramp closed
	OutcomeCovered    = "covered"     // predicted possible, ramp closed
	OutcomeMiss       = "miss"        // predicted none, ramp closed
	OutcomeFalseAlarm = "false_alarm" // predicted likely, ramp stayed open
	OutcomeHedged     = "hedged"      // predicted possible, ramp stayed open
	OutcomeQuiet      = "quiet"       // predicted none, ramp stayed open
)

// PeakGrade grades one ramp against one daytime tide peak.
type PeakGrade struct {
	PeakTime time.Time `json:"peak_time"`
	PeakFt   float64   `json:"peak_ft"`
	Risk     string    `json:"risk"`
	Closed   bool      `json:"closed"`
	Outcome  string    `json:"outcome"`

	// Sea state nearest the peak (within maxWaveMatchGap), when the wave
	// series has it — so misses and false alarms can be read against the
	// surf that day, not just the tide.
	WaveHeightFt    *float64   `json:"wave_height_ft,omitempty"`
	DominantPeriodS *float64   `json:"dominant_period_s,omitempty"`
	WaveObservedAt  *time.Time `json:"wave_observed_at,omitempty"`

	// Window grading, present only when the model would have drawn a window
	// (risk possible/likely) and the ramp actually closed.
	Window     *Window    `json:"window,omitempty"`
	ClosedAt   *time.Time `json:"closed_at,omitempty"`
	ReopenedAt *time.Time `json:"reopened_at,omitempty"`
	WindowHit  *bool      `json:"window_hit,omitempty"`
}

// RampGrade is one ramp's scorecard for the day.
type RampGrade struct {
	AccessID    string      `json:"access_id"`
	ThresholdFt float64     `json:"threshold_ft"`
	Learned     bool        `json:"learned"`
	Peaks       []PeakGrade `json:"peaks"`
}

// ScorecardSummary aggregates outcomes across every graded (ramp, peak) pair.
type ScorecardSummary struct {
	Graded      int `json:"graded"`
	Hits        int `json:"hits"`
	Covered     int `json:"covered"`
	Misses      int `json:"misses"`
	FalseAlarms int `json:"false_alarms"`
	Hedged      int `json:"hedged"`
	Quiet       int `json:"quiet"`

	// Recall: of the peaks that actually closed a ramp, how many the model
	// flagged (likely or possible). Precision: of the "likely" calls, how many
	// closed. Nil when the denominator is empty.
	Recall    *float64 `json:"recall,omitempty"`
	Precision *float64 `json:"precision,omitempty"`

	// WindowHits / WindowGraded: of the closures the model flagged, how many
	// began inside the predicted window.
	WindowHits   int `json:"window_hits"`
	WindowGraded int `json:"window_graded"`
}

// Scorecard grades one past day's outlook against recorded reality.
type Scorecard struct {
	Date   string `json:"date"`
	Season string `json:"season"`

	// ParamsComputedAt is when the graded parameter set was trained. The
	// nightly trainer already folded the graded day into these params, so the
	// scorecard is a mildly optimistic view of what was served live that day.
	ParamsComputedAt time.Time `json:"params_computed_at,omitzero"`

	// WaveParams echoes the wave regime split the grades were computed
	// under, nil when the graded params were tide-only.
	WaveParams *WaveParams `json:"wave_params,omitempty"`

	Peaks   []models.TidePrediction `json:"peaks"`
	Ramps   []RampGrade             `json:"ramps"`
	Summary ScorecardSummary        `json:"summary"`
}

// outcomeFor maps a predicted risk and the observed truth to an outcome.
func outcomeFor(risk string, closed bool) string {
	switch {
	case risk == RiskLikely && closed:
		return OutcomeHit
	case risk == RiskPossible && closed:
		return OutcomeCovered
	case closed:
		return OutcomeMiss
	case risk == RiskLikely:
		return OutcomeFalseAlarm
	case risk == RiskPossible:
		return OutcomeHedged
	default:
		return OutcomeQuiet
	}
}

// matchClosure finds the closure episode a peak belongs to: the episode
// containing the peak, else the nearest start within peakMatchWindow.
func matchClosure(peak models.TidePrediction, closures []closureEvent) *closureEvent {
	var nearest *closureEvent
	bestDelta := peakMatchWindow
	for i := range closures {
		c := &closures[i]
		if peak.Time.After(c.closedAt) && (c.reopenedAt.IsZero() || peak.Time.Before(c.reopenedAt)) {
			return c
		}
		d := peak.Time.Sub(c.closedAt)
		if d < 0 {
			d = -d
		}
		if d <= bestDelta {
			bestDelta = d
			nearest = c
		}
	}
	return nearest
}

// BuildScorecard replays date's daytime tide peaks through the model's risk
// rules and grades each call against the recorded closure history. date is
// interpreted as an Eastern calendar day. closureHeights carries any
// operator-set ramp_metadata overrides keyed by access_id, so grading uses
// the same effective threshold the live outlook would. waves is the buoy
// series covering the day (any order; nil is fine) — it annotates each grade
// with the sea state nearest the peak. Pure — no I/O.
func BuildScorecard(date time.Time, historyByRamp map[string][]models.StatusEvent, closureHeights map[string]*float64, params Params, preds []models.TidePrediction, waves []models.WaveSample) Scorecard {
	sortWaveSamples(waves)
	et := date.In(eastern)
	dayStart := time.Date(et.Year(), et.Month(), et.Day(), 0, 0, 0, 0, eastern)
	dayEnd := dayStart.AddDate(0, 0, 1)

	// The day's schedule, framed from early morning so buildSchedule never
	// rolls to the next day.
	season, sched := buildSchedule(dayStart.Add(5*time.Hour), params)

	// Daytime peaks on the target date.
	var dayPeaks []models.TidePrediction
	for _, p := range tidePeaks(preds) {
		if !p.Time.Before(dayStart) && p.Time.Before(dayEnd) {
			dayPeaks = append(dayPeaks, p)
		}
	}

	sc := Scorecard{
		Date:             dayStart.Format("2006-01-02"),
		Season:           season,
		ParamsComputedAt: params.ComputedAt,
		WaveParams:       params.Waves,
		Peaks:            dayPeaks,
		Ramps:            []RampGrade{},
	}
	if len(dayPeaks) == 0 {
		return sc
	}

	accessIDs := make([]string, 0, len(historyByRamp))
	for id := range historyByRamp {
		accessIDs = append(accessIDs, id)
	}
	sort.Strings(accessIDs)

	for _, accessID := range accessIDs {
		events := historyByRamp[accessID]
		// Only grade ramps whose history had started by the graded day.
		if len(events) == 0 || events[0].RecordedAt.After(dayStart) {
			continue
		}

		rp, learned := effectiveParams(accessID, closureHeights[accessID], params)
		closures := closureEvents(events)
		labels := labelPeaks(dayPeaks, closures)

		rg := RampGrade{
			AccessID:    accessID,
			ThresholdFt: rp.ThresholdFt,
			Learned:     learned,
			Peaks:       make([]PeakGrade, 0, len(dayPeaks)),
		}

		for i, peak := range dayPeaks {
			// Grade with the same wave shift the live model would have used
			// at this peak — grading and serving stay one decision surface.
			var waveFt *float64
			w := waveNearTime(waves, peak.Time)
			if w != nil {
				waveFt = &w.HeightFt
			}
			risk := riskForPeak(*peak.Height, params.waveShift(waveFt), rp, params.hardOpen(), params.hardClose())
			closed := labels[i]
			pg := PeakGrade{
				PeakTime: peak.Time,
				PeakFt:   *peak.Height,
				Risk:     risk,
				Closed:   closed,
				Outcome:  outcomeFor(risk, closed),
			}
			if w != nil {
				h := w.HeightFt
				at := w.Time
				pg.WaveHeightFt = &h
				pg.DominantPeriodS = w.DominantPeriodS
				pg.WaveObservedAt = &at
			}

			if closed && riskRank(risk) >= 1 {
				pg.Window = closureWindow(peak, rp, sched)
				if c := matchClosure(peak, closures); c != nil {
					closedAt := c.closedAt
					pg.ClosedAt = &closedAt
					if !c.reopenedAt.IsZero() {
						reopenedAt := c.reopenedAt
						pg.ReopenedAt = &reopenedAt
					}
					if pg.Window != nil {
						hit := !closedAt.Before(pg.Window.Start) && !closedAt.After(pg.Window.End)
						pg.WindowHit = &hit
						sc.Summary.WindowGraded++
						if hit {
							sc.Summary.WindowHits++
						}
					}
				}
			}

			switch pg.Outcome {
			case OutcomeHit:
				sc.Summary.Hits++
			case OutcomeCovered:
				sc.Summary.Covered++
			case OutcomeMiss:
				sc.Summary.Misses++
			case OutcomeFalseAlarm:
				sc.Summary.FalseAlarms++
			case OutcomeHedged:
				sc.Summary.Hedged++
			case OutcomeQuiet:
				sc.Summary.Quiet++
			}
			sc.Summary.Graded++
			rg.Peaks = append(rg.Peaks, pg)
		}

		sc.Ramps = append(sc.Ramps, rg)
	}

	if closedTotal := sc.Summary.Hits + sc.Summary.Covered + sc.Summary.Misses; closedTotal > 0 {
		r := round3(float64(sc.Summary.Hits+sc.Summary.Covered) / float64(closedTotal))
		sc.Summary.Recall = &r
	}
	if likelyTotal := sc.Summary.Hits + sc.Summary.FalseAlarms; likelyTotal > 0 {
		p := round3(float64(sc.Summary.Hits) / float64(likelyTotal))
		sc.Summary.Precision = &p
	}

	return sc
}

func round3(v float64) float64 {
	return math.Round(v*1000) / 1000
}
