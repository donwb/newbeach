package predict

import (
	"math"
	"time"

	"github.com/donwb/beach/api/internal/models"
	"github.com/donwb/beach/api/internal/solar"
)

// Risk levels, mildest first. none/possible/likely grade one thing only —
// the chance the tide closes this ramp — and the backtest and scorecard
// read them that way, so nothing else may borrow them. The other two are
// factual states, not gambles: closed_now means the ramp is shut right now
// (tide, or overnight) and carries a reopen estimate; scheduled means the
// only closure coming is the driving day ending, which is not in doubt.
const (
	RiskNone      = "none"
	RiskPossible  = "possible"
	RiskLikely    = "likely"
	RiskScheduled = "scheduled"
	RiskClosedNow = "closed_now"
)

// Closure reasons. Every predicted closure has one of exactly two causes:
// the tide pushing the county off the beach, or the driving day simply
// ending. The strings are informational — the copy already names the
// reason — but they let a client branch (icon, color) without parsing prose.
const (
	ReasonHighTide  = "high_tide"
	ReasonEndOfDay  = "end_of_day"
	ReasonOvernight = "overnight"
)

// Hard county-wide rules from the historical analysis: peaks at or above
// hardCloseFt closed essentially everything; peaks at or below hardOpenFt
// closed nothing.
const (
	hardCloseFt = 3.5
	hardOpenFt  = 2.0

	// hysteresisFt is the half-width of the "could go either way" band
	// around a ramp's learned threshold.
	hysteresisFt = 0.3

	// midRangeFt/midRangeCloseRate: below its threshold band, a ramp that
	// still closes this often around peaks keeps a "possible" instead of
	// "none" once the peak reaches the county's observed action zone.
	midRangeFt        = 2.4
	midRangeCloseRate = 0.35

	// windowPadding is added on both sides of the learned lead/lag offsets
	// so the window reads as the rough stretch it is.
	windowPadding = 45 * time.Minute

	// peakLookback is how far behind now a high-tide peak stays in play. A
	// peak the clock has passed is not automatically harmless — the county
	// closes late as often as early — so peaks stay in the running until
	// their learned lag runs out (see decayRisk). Comfortably past the
	// largest lag we have ever learned.
	peakLookback = 3 * time.Hour

	// reopenAfterLow is the fallback reopen estimate: the county tends to
	// reopen roughly this long after the low tide that follows a closure.
	reopenAfterLow = 90 * time.Minute
)

// Window is a coarse predicted closure window, pre-rounded to half hours so
// clients can shade it without implying precision.
type Window struct {
	Label string    `json:"label"`
	Start time.Time `json:"start"`
	End   time.Time `json:"end"`
}

// Reopen carries only a casual label — never a clock time.
type Reopen struct {
	Label string `json:"label"`
}

// RampOutlook is one ramp's tide outlook for the rest of the driving day.
// Short is a compact hint for tight spots (board cards); like every string
// here it is rendered verbatim by clients.
type RampOutlook struct {
	AccessID   string  `json:"access_id"`
	RampID     int64   `json:"ramp_id"`
	City       string  `json:"city,omitempty"` // raw GIS key, matches ramp .city
	Risk       string  `json:"risk"`
	Reason     string  `json:"reason,omitempty"`
	Confidence string  `json:"confidence"`
	Headline   string  `json:"headline"`
	Detail     string  `json:"detail,omitempty"`
	Short      string  `json:"short,omitempty"`
	Window     *Window `json:"window,omitempty"`
	Reopen     *Reopen `json:"reopen,omitempty"`

	// quotedClose is the clock time this ramp's own copy quotes for the
	// tide closure (peak minus lead when likely, the peak itself when only
	// possible). The city verdict aggregates it so "first around" never
	// names an hour no ramp line mentions. Not serialized.
	quotedClose *time.Time
}

// Schedule is the driving-hours frame for the day: fixed clock hours in
// turtle season, sunrise-to-sunset otherwise.
type Schedule struct {
	OpensLabel  string     `json:"opens_label"`
	ClosesLabel string     `json:"closes_label"`
	OpensAt     *time.Time `json:"opens_at,omitempty"`
	ClosesAt    *time.Time `json:"closes_at,omitempty"`
}

// TideContext is the shared tide backdrop for the outlook.
type TideContext struct {
	NextPeakFt *float64   `json:"next_peak_ft,omitempty"`
	NextPeakAt *time.Time `json:"next_peak_at,omitempty"`
}

// SurfContext is the sea state the outlook was computed under — present only
// when a fresh buoy observation informed the risk calls, so an operator can
// always see what the model saw. Regime names which learned wave regime
// applied (calm/neutral/rough), empty when no wave params are trained yet.
type SurfContext struct {
	WaveHeightFt    float64   `json:"wave_height_ft"`
	DominantPeriodS *float64  `json:"dominant_period_s,omitempty"`
	ObservedAt      time.Time `json:"observed_at"`
	Regime          string    `json:"regime,omitempty"`
}

// Outlook is the full response served at /api/v2/outlook. SurfReport is the
// casual surf line (a product feature with its own kill switch), attached by
// the service after BuildOutlook — distinct from Surf, the model echo.
type Outlook struct {
	GeneratedAt time.Time     `json:"generated_at"`
	Season      string        `json:"season"`
	Schedule    Schedule      `json:"schedule"`
	Tide        TideContext   `json:"tide"`
	Surf        *SurfContext  `json:"surf,omitempty"`
	SurfReport  *SurfReport   `json:"surf_report,omitempty"`
	Ramps       []RampOutlook `json:"ramps"`
	Cities      []CityVerdict `json:"cities,omitempty"`
}

// inTurtleSeason reports whether the Eastern date falls in Volusia County's
// sea-turtle nesting season, May 1 through October 31.
func inTurtleSeason(t time.Time) bool {
	m := t.In(eastern).Month()
	return m >= time.May && m <= time.October
}

// postedHours returns the county's nominal driving hours for the Eastern
// calendar day containing t: fixed 8am–7pm in turtle season, sunrise to
// fifteen minutes before sunset otherwise.
func postedHours(t time.Time) (opens, closes time.Time, ok bool) {
	et := t.In(eastern)
	if inTurtleSeason(t) {
		opens = time.Date(et.Year(), et.Month(), et.Day(), 8, 0, 0, 0, eastern)
		closes = time.Date(et.Year(), et.Month(), et.Day(), 19, 0, 0, 0, eastern)
		return opens, closes, true
	}
	sunrise, sunset := solar.Events(t, solar.NSB)
	if sunrise == nil || sunset == nil {
		return time.Time{}, time.Time{}, false
	}
	return *sunrise, sunset.Add(-15 * time.Minute), true
}

// buildSchedule derives the day's driving-hours frame, rolling to tomorrow
// once today's driving is done. The close carries the learned offset: the
// posted time is policy, but this is a prediction, so it should say when the
// county actually clears the beach.
func buildSchedule(now time.Time, params Params) (string, Schedule) {
	season := "standard"
	if inTurtleSeason(now) {
		season = "turtle"
	}

	opens, closes, ok := postedHours(now)
	if !ok {
		return season, Schedule{OpensLabel: "around sunrise", ClosesLabel: "around sunset"}
	}
	closes = closes.Add(params.dayCloseOffset())
	if !now.Before(closes) {
		nextOpens, nextCloses, nextOK := postedHours(now.AddDate(0, 0, 1))
		if !nextOK {
			return season, Schedule{OpensLabel: "around sunrise", ClosesLabel: "around sunset"}
		}
		opens, closes = nextOpens, nextCloses.Add(params.dayCloseOffset())
	}

	sched := Schedule{OpensAt: &opens, ClosesAt: &closes}
	// Labels carry approximate clock times in the same half-hour-rounded
	// voice as the rest of the copy.
	if season == "turtle" {
		sched.OpensLabel = "around " + fmtClock(roundNearest30(opens)) + ", once ramps are cleared for turtles"
		sched.ClosesLabel = fmtClock(roundNearest30(closes))
	} else {
		sched.OpensLabel = "sunrise (~" + fmtClock(roundNearest30(opens)) + ")"
		sched.ClosesLabel = "sunset (~" + fmtClock(roundNearest30(closes)) + ")"
	}
	return season, sched
}

// effectiveParams resolves a ramp's parameters: learned when available,
// county default otherwise, with an operator-set closure height from
// ramp_metadata overriding the learned threshold.
func effectiveParams(accessID string, closureHeightFt *float64, params Params) (RampParams, bool) {
	rp, learned := params.Ramps[accessID]
	if !learned {
		rp = params.Default
	}
	if closureHeightFt != nil && *closureHeightFt > 0 {
		rp.ThresholdFt = *closureHeightFt
		// The operator's threshold is authoritative — don't let the learned
		// base rate second-guess it via the mid-range rule.
		rp.CloseRate = 0
	}
	return rp, learned
}

// confidence buckets how much to trust a ramp's learned behavior.
func confidence(rp RampParams, learned bool) string {
	switch {
	case !learned || rp.NClosures < 10:
		return "low"
	case rp.Accuracy >= 0.7 && rp.NClosures >= 20:
		return "high"
	default:
		return "medium"
	}
}

// riskForPeak classifies one predicted peak against a ramp's parameters.
// hardOpen/hardClose are the county-wide cutoffs (learned percentiles of the
// peak distribution, so they track the configured station's height scale).
//
// waveShiftFt moves the learnable band with the current sea state — positive
// on calm water, negative under a swell, 0 when wave data is missing. The
// asymmetry is deliberate: surf evidence can silence a call or hedge it, but
// only tide evidence promotes to "likely" (a swell never lowers the likely
// bar — it widens the possible band downward instead), and the hard cutoffs
// don't move at all: extreme tides close ramps regardless of surf, so recall
// at the top end never depends on the buoy.
func riskForPeak(peakFt, waveShiftFt float64, rp RampParams, hardOpen, hardClose float64) string {
	likelyShift := math.Max(waveShiftFt, 0)
	switch {
	case peakFt >= hardClose:
		return RiskLikely
	case peakFt <= hardOpen:
		return RiskNone
	case peakFt >= rp.ThresholdFt+likelyShift+hysteresisFt:
		return RiskLikely
	case peakFt >= rp.ThresholdFt+waveShiftFt-hysteresisFt:
		return RiskPossible
	case peakFt >= midRangeFt+waveShiftFt && rp.CloseRate >= midRangeCloseRate:
		return RiskPossible
	default:
		return RiskNone
	}
}

func riskRank(r string) int {
	switch r {
	case RiskLikely:
		return 2
	case RiskPossible:
		return 1
	default:
		return 0
	}
}

// decayRisk softens a peak's risk as the clock overtakes it, for a ramp
// that is still open. The learned lead/lag are medians, so passing the
// predicted close time means the closure is late, not cancelled — but once
// the peak itself is behind us the water is falling and the ramp has
// already beaten this tide, so "likely" drops to "possible". Past the
// learned lag the peak stops counting altogether.
func decayRisk(risk string, now time.Time, peak models.TidePrediction, rp RampParams) string {
	if riskRank(risk) == 0 {
		return risk
	}
	if !now.Before(peak.Time.Add(time.Duration(rp.LagMin) * time.Minute)) {
		return RiskNone
	}
	if risk == RiskLikely && !now.Before(peak.Time) {
		return RiskPossible
	}
	return risk
}

// roundDown30/roundUp30 snap times to half-hour boundaries in Eastern time.
func roundDown30(t time.Time) time.Time {
	et := t.In(eastern)
	return et.Truncate(30 * time.Minute)
}

func roundUp30(t time.Time) time.Time {
	down := roundDown30(t)
	if down.Equal(t.In(eastern)) {
		return down
	}
	return down.Add(30 * time.Minute)
}

// closureWindow builds the coarse window around a peak, clamped to the
// driving day.
func closureWindow(peak models.TidePrediction, rp RampParams, sched Schedule) *Window {
	start := peak.Time.Add(-time.Duration(rp.LeadMin)*time.Minute - windowPadding)
	end := peak.Time.Add(time.Duration(rp.LagMin)*time.Minute + windowPadding)
	if sched.OpensAt != nil && start.Before(*sched.OpensAt) {
		start = *sched.OpensAt
	}
	if sched.ClosesAt != nil && end.After(*sched.ClosesAt) {
		end = *sched.ClosesAt
	}
	if !end.After(start) {
		return nil
	}
	start = roundDown30(start)
	end = roundUp30(end)
	return &Window{Label: clockRange(start, end), Start: start, End: end}
}

// heightAtCos interpolates the tide height at t between hilo extremes using
// the half-cosine curve tides actually follow.
func heightAtCos(preds []models.TidePrediction, t time.Time) (float64, bool) {
	for i := 1; i < len(preds); i++ {
		p0, p1 := preds[i-1], preds[i]
		if p0.Height == nil || p1.Height == nil {
			continue
		}
		if t.Before(p0.Time) || t.After(p1.Time) {
			continue
		}
		span := p1.Time.Sub(p0.Time).Seconds()
		if span <= 0 {
			return *p0.Height, true
		}
		frac := t.Sub(p0.Time).Seconds() / span
		blend := (1 - math.Cos(frac*math.Pi)) / 2
		return *p0.Height + (*p1.Height-*p0.Height)*blend, true
	}
	return 0, false
}

// reopenEstimate ports the web client's falling-limb estimator: the water
// that forced the closure recedes to the same height on the way down, so the
// reopen estimate is the falling curve's return to the closure-time height.
// Fallback: the low tide after the closure plus the county-practice offset.
// Returns zero time when nothing applies.
func reopenEstimate(preds []models.TidePrediction, closedAt, now time.Time) time.Time {
	if closureHeight, ok := heightAtCos(preds, closedAt); ok {
		// Only meaningful when the closure precedes a high — i.e. the tide
		// was still coming up.
		var nextExt *models.TidePrediction
		for i := range preds {
			if preds[i].Time.After(closedAt) {
				nextExt = &preds[i]
				break
			}
		}
		if nextExt != nil && nextExt.Type == "H" {
			limit := closedAt.Add(30 * time.Hour)
			step := 5 * time.Minute
			prev := nextExt.Time
			for t := prev.Add(step); t.Before(limit); t = t.Add(step) {
				h, ok := heightAtCos(preds, t)
				if !ok {
					break
				}
				if h <= closureHeight {
					lo, hi := prev, t
					for i := 0; i < 20; i++ {
						mid := lo.Add(hi.Sub(lo) / 2)
						if m, ok := heightAtCos(preds, mid); ok && m <= closureHeight {
							hi = mid
						} else {
							lo = mid
						}
					}
					if hi.After(now) {
						return hi
					}
					break
				}
				prev = t
			}
		}
	}

	for _, p := range preds {
		if p.Type == "L" && p.Time.After(closedAt) {
			reopen := p.Time.Add(reopenAfterLow)
			if reopen.After(now) {
				return reopen
			}
			break
		}
	}
	return time.Time{}
}

// BuildOutlook computes the full outlook. preds are hilo predictions
// covering at least [now-1d, now+2d]; ramps come from
// GetRampsWithStatusSince. wave is the latest buoy observation, nil when
// unavailable; an observation older than maxWaveAge is ignored, so a drifting
// or silent buoy degrades cleanly to tide-only behavior. Pure — no I/O,
// fully testable.
func BuildOutlook(now time.Time, ramps []models.RampStatusWithSince, params Params, preds []models.TidePrediction, wave *models.WaveSample) Outlook {
	season, sched := buildSchedule(now, params)

	out := Outlook{
		GeneratedAt: now.UTC(),
		Season:      season,
		Schedule:    sched,
		Ramps:       make([]RampOutlook, 0, len(ramps)),
	}

	// One shift for the whole response: the sea state is county-wide.
	waveShiftFt := 0.0
	if wave != nil {
		age := now.Sub(wave.Time)
		if age < 0 {
			age = -age
		}
		if age <= maxWaveAge {
			waveShiftFt = params.waveShift(&wave.HeightFt)
			surf := SurfContext{
				WaveHeightFt:    wave.HeightFt,
				DominantPeriodS: wave.DominantPeriodS,
				ObservedAt:      wave.Time,
			}
			if w := params.Waves; w != nil {
				switch {
				case wave.HeightFt <= w.CalmMaxFt:
					surf.Regime = "calm"
				case wave.HeightFt >= w.RoughMinFt:
					surf.Regime = "rough"
				default:
					surf.Regime = "neutral"
				}
			}
			out.Surf = &surf
		}
	}

	// Shared tide context: the next high-tide peak from now.
	for i := range preds {
		if preds[i].Type == "H" && preds[i].Time.After(now) && preds[i].Height != nil {
			out.Tide.NextPeakFt = preds[i].Height
			t := preds[i].Time
			out.Tide.NextPeakAt = &t
			break
		}
	}

	// Peaks that could disturb the current driving day: highs from the
	// recent past (still inside their closure lag) through the day's close.
	var dayPeaks []models.TidePrediction
	for _, p := range preds {
		if p.Type != "H" || p.Height == nil || p.Time.Before(now.Add(-peakLookback)) {
			continue
		}
		if sched.ClosesAt != nil && p.Time.After(sched.ClosesAt.Add(time.Hour)) {
			continue
		}
		dayPeaks = append(dayPeaks, p)
	}

	for _, ramp := range ramps {
		rp, learned := effectiveParams(ramp.AccessID, ramp.ClosureHeightFt, params)
		ro := RampOutlook{
			AccessID:   ramp.AccessID,
			RampID:     ramp.ID,
			City:       ramp.City,
			Confidence: confidence(rp, learned),
		}

		// Outside driving hours nothing is open and no tide matters — the
		// next thing that happens is the morning open, so say that.
		if sched.OpensAt != nil && now.Before(*sched.OpensAt) {
			ro.Risk = RiskClosedNow
			ro.Reason = ReasonOvernight
			ro.Headline, ro.Detail, ro.Reopen = beforeOpenText(season, sched)
			out.Ramps = append(out.Ramps, ro)
			continue
		}

		if ramp.AccessStatus == tideClosedStatus {
			ro.Risk = RiskClosedNow
			ro.Reason = ReasonHighTide
			closedAt := now
			if ramp.StatusSince != nil {
				closedAt = *ramp.StatusSince
			}
			reopen := reopenEstimate(preds, closedAt, now)
			ro.Headline, ro.Detail, ro.Reopen = closedNowText(reopen, sched)
			out.Ramps = append(out.Ramps, ro)
			continue
		}

		// Riskiest remaining peak wins; note a later troublesome peak.
		risk := RiskNone
		var riskPeak *models.TidePrediction
		riskIdx := -1
		risks := make([]string, len(dayPeaks))
		for i := range dayPeaks {
			r := riskForPeak(*dayPeaks[i].Height, waveShiftFt, rp, params.hardOpen(), params.hardClose())
			risks[i] = decayRisk(r, now, dayPeaks[i], rp)
			if riskRank(risks[i]) > riskRank(risk) {
				risk = risks[i]
				riskPeak = &dayPeaks[i]
				riskIdx = i
			}
		}
		var laterPeakRisky bool
		for i := riskIdx + 1; i > 0 && i < len(dayPeaks); i++ {
			if riskRank(risks[i]) >= 1 {
				laterPeakRisky = true
			}
		}

		// A live tide risk is the nearer, less certain story, so it wins;
		// otherwise the end of the driving day is the closure to warn about.
		switch {
		case riskPeak != nil && riskRank(risk) >= 1:
			ro.Risk = risk
			ro.Reason = ReasonHighTide
			ro.Window = closureWindow(*riskPeak, rp, sched)
			qc := quotedCloseAt(risk, *riskPeak, rp)
			ro.quotedClose = &qc
			ro.Headline, ro.Detail, ro.Short = tideText(now, risk, *riskPeak, rp, sched, laterPeakRisky)
		case sched.ClosesAt != nil:
			// No tide story, so the next scheduled thing is the day ending.
			// This line always looks forward — it is never a place to say
			// what already happened.
			ro.Risk = RiskScheduled
			ro.Reason = ReasonEndOfDay
			ro.Headline, ro.Detail, ro.Short = endOfDayText(season, sched)
		default:
			ro.Risk = RiskNone
			ro.Headline, ro.Detail = quietText(sched)
		}
		out.Ramps = append(out.Ramps, ro)
	}

	out.Cities = buildCityVerdicts(now, ramps, out.Ramps, sched, season, out.Tide)
	return out
}
