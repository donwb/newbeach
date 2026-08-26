package predict

import (
	"fmt"
	"math"
	"sort"
	"time"

	"github.com/donwb/beach/api/internal/models"
)

const (
	tideClosedStatus = "CLOSED FOR HIGH TIDE"

	// minClosuresForRamp is the smallest closure sample that earns a ramp its
	// own learned parameters; below it the county default applies.
	minClosuresForRamp = 5

	// peakMatchWindow bounds how far a closure can sit from a tide peak and
	// still be attributed to it.
	peakMatchWindow = 4 * time.Hour

	// Threshold candidates are scanned over this clamped range (ft MLLW,
	// station-8721147 scale) when the peak distribution can't provide one.
	minThresholdFt = 1.5
	maxThresholdFt = 4.5

	// Wave-regime learning guards: the pool must be at least this big to
	// learn anything, each regime needs this many labeled peaks to earn a
	// shift, and a nonzero shift must beat shift-0 accuracy within its
	// regime by at least minWaveGain — otherwise the shift stays 0 and the
	// model behaves exactly tide-only.
	minWavePoolSamples   = 30
	minWaveRegimeSamples = 15
	minWaveGain          = 0.02
	waveShiftStepFt      = 0.05

	// Persistence-prior guards, the same shape: a pool floor, a per-side
	// floor, and a minimum gain over shift 0 before a shift is believed.
	minPersistPoolSamples = 30
	minPersistSideSamples = 15
	minPersistGain        = 0.02
)

// peakQuantile returns the q-quantile of the peak heights (nearest rank).
func peakQuantile(peaks []models.TidePrediction, q float64) float64 {
	if len(peaks) == 0 {
		return 0
	}
	heights := make([]float64, 0, len(peaks))
	for _, p := range peaks {
		heights = append(heights, *p.Height)
	}
	sort.Float64s(heights)
	idx := int(q * float64(len(heights)-1))
	return heights[idx]
}

// closureEvent is one contiguous CLOSED FOR HIGH TIDE episode.
type closureEvent struct {
	closedAt   time.Time
	reopenedAt time.Time // zero when still closed at the end of history
}

// closureEvents extracts tide-closure episodes from a ramp's ascending
// status-event history.
func closureEvents(events []models.StatusEvent) []closureEvent {
	var out []closureEvent
	openIdx := -1
	for _, e := range events {
		isTide := e.AccessStatus == tideClosedStatus
		if isTide && openIdx < 0 {
			// Transitions into tide-closed. The very first event of history
			// being tide-closed still counts as a closure start.
			out = append(out, closureEvent{closedAt: e.RecordedAt})
			openIdx = len(out) - 1
		}
		if !isTide && openIdx >= 0 {
			out[openIdx].reopenedAt = e.RecordedAt
			openIdx = -1
		}
	}
	return out
}

// tidePeaks filters hilo predictions down to high-tide peaks with heights,
// keeping only those within the county's plausible driving day (7am–8pm ET) —
// overnight peaks can't cause an observable closure.
func tidePeaks(preds []models.TidePrediction) []models.TidePrediction {
	var peaks []models.TidePrediction
	for _, p := range preds {
		if p.Type != "H" || p.Height == nil {
			continue
		}
		h := p.Time.In(eastern).Hour()
		if h >= 7 && h < 20 {
			peaks = append(peaks, p)
		}
	}
	return peaks
}

// labelPeaks marks, for each daytime peak, whether the ramp was tide-closed
// around it: either the closure began within peakMatchWindow of the peak, or
// the peak fell inside a closure episode.
func labelPeaks(peaks []models.TidePrediction, closures []closureEvent) []bool {
	labels := make([]bool, len(peaks))
	for i, p := range peaks {
		for _, c := range closures {
			startDelta := p.Time.Sub(c.closedAt)
			if startDelta < 0 {
				startDelta = -startDelta
			}
			within := startDelta <= peakMatchWindow
			during := p.Time.After(c.closedAt) && (c.reopenedAt.IsZero() || p.Time.Before(c.reopenedAt))
			if within || during {
				labels[i] = true
				break
			}
		}
	}
	return labels
}

// bestThreshold scans candidate peak-height thresholds and returns the one
// maximizing plain accuracy over labeled peaks. Plain (not balanced)
// accuracy is deliberate: each ramp's closure base rate is real signal — a
// ramp that rides out most high tides should carry a high threshold, and one
// that closes for nearly any peak a low one. Balanced accuracy would erase
// exactly that per-ramp difference.
func bestThreshold(peaks []models.TidePrediction, labels []bool) (threshold, accuracy float64) {
	var nClosed, nOpen int
	for _, l := range labels {
		if l {
			nClosed++
		} else {
			nOpen++
		}
	}
	if nClosed == 0 || nOpen == 0 {
		return DefaultParams.ThresholdFt, 0
	}

	// Scan candidates across the observed peak range so the search adapts
	// to the configured station's height scale.
	lo, hi := minThresholdFt, maxThresholdFt
	if len(peaks) > 0 {
		lo, hi = peakQuantile(peaks, 0), peakQuantile(peaks, 1)
	}

	best := DefaultParams.ThresholdFt
	bestAcc := -1.0
	total := float64(len(labels))
	for th := lo; th <= hi+1e-9; th += 0.05 {
		var correct int
		for i, p := range peaks {
			if (*p.Height >= th) == labels[i] {
				correct++
			}
		}
		acc := float64(correct) / total
		if acc > bestAcc {
			bestAcc = acc
			best = th
		}
	}
	return math.Round(best*100) / 100, math.Round(bestAcc*1000) / 1000
}

// leadLag computes the median minutes between closure start and the nearest
// peak (lead) and between peak and reopen (lag). Closures with no matching
// peak or no reopen are skipped for the respective statistic.
func leadLag(peaks []models.TidePrediction, closures []closureEvent) (leadMin, lagMin int, matched int) {
	var leads, lags []float64
	for _, c := range closures {
		var nearest *models.TidePrediction
		bestDelta := peakMatchWindow
		for i := range peaks {
			d := peaks[i].Time.Sub(c.closedAt)
			if d < 0 {
				d = -d
			}
			if d <= bestDelta {
				bestDelta = d
				nearest = &peaks[i]
			}
		}
		if nearest == nil {
			continue
		}
		matched++
		leads = append(leads, nearest.Time.Sub(c.closedAt).Minutes())
		if !c.reopenedAt.IsZero() {
			lags = append(lags, c.reopenedAt.Sub(nearest.Time).Minutes())
		}
	}
	return int(math.Round(median(leads))), int(math.Round(median(lags))), matched
}

func median(vals []float64) float64 {
	if len(vals) == 0 {
		return 0
	}
	s := append([]float64(nil), vals...)
	sort.Float64s(s)
	mid := len(s) / 2
	if len(s)%2 == 1 {
		return s[mid]
	}
	return (s[mid-1] + s[mid]) / 2
}

// dayCloseStatus is the plain closed state the county sets when it clears
// the beach at the end of the driving day (as opposed to the tide- and
// turtle-specific strings).
const dayCloseStatus = "CLOSED"

// dayCloseOffsets measures how far each end-of-day close ran from the
// posted close for that date. One sample per ramp-day: the transition into
// plain CLOSED that happens in the back half of the day. Negative values
// mean the county cleared the beach early, which is the observed norm.
func dayCloseOffsets(historyByRamp map[string][]models.StatusEvent) []float64 {
	var offsets []float64
	for _, events := range historyByRamp {
		seen := map[string]bool{}
		var prev string
		for _, e := range events {
			transition := prev != dayCloseStatus && e.AccessStatus == dayCloseStatus
			prev = e.AccessStatus
			if !transition {
				continue
			}
			et := e.RecordedAt.In(eastern)
			// Only the evening clear-out; a midday CLOSED is something else.
			if et.Hour() < 12 {
				continue
			}
			day := et.Format("2006-01-02")
			if seen[day] {
				continue
			}
			_, posted, ok := postedHours(et)
			if !ok {
				continue
			}
			delta := et.Sub(posted).Minutes()
			if math.Abs(delta) > maxDayCloseOffsetMin {
				continue
			}
			seen[day] = true
			offsets = append(offsets, delta)
		}
	}
	return offsets
}

// minDayCloseSamples is the smallest sample that earns a learned end-of-day
// offset; below it the posted close stands.
const minDayCloseSamples = 10

// wavePeakSample is one labeled daytime peak with its ramp's learned tide
// threshold and the sea state nearest the peak — the unit the county-wide
// wave regime split trains on.
type wavePeakSample struct {
	peakFt      float64
	thresholdFt float64
	closeRate   float64 // the ramp's base rate, for riskForPeak's mid-range rule
	label       bool
	waveFt      float64
	hardOpen    float64 // county cutoffs at training time; 0 = package defaults
	hardClose   float64
}

// closedPeakWeight makes a closure peak worth this many quiet peaks when a
// regime's fixed error is weighed against another's. The outcome taxonomy is
// asymmetric on purpose — a hedge that doesn't fire costs nothing, a missed
// closure is the worst outcome — so the learner that can *suppress* risk
// must price a new miss higher than a saved false alarm. (bestThreshold
// stays plain-accuracy: per-ramp base rates are signal there.)
const closedPeakWeight = 2.0

// Grade costs for the shift scans, in scorecard-outcome terms. A shift is
// judged by the call the live engine would actually make under it — the
// three-level riskForPeak grade, not a binary closed/open cut — because a
// raise that only demotes "likely" to "possible" on a ramp that still
// closes half the time is the free hedge the taxonomy says it is, not a
// miss. A binary scan charged those as misses and so never learned to
// quiet the eager ramps (five straight false "likely" days on NS-141 at
// 2.5 ft, calm water, after open days — 2026-08-17..21).
const (
	costMiss       = 2.0  // none, closed — the worst outcome
	costFalseAlarm = 1.0  // likely, open
	costCovered    = 0.5  // possible, closed — caught, but a hit would have been better
	costHedged     = 0.25 // possible, open — a little decisiveness spent
)

// gradeScore scores a shift over the samples as 1 − mean cost/costMiss, so
// 1.0 is every call a hit or quiet and higher is better. The call is the
// real riskForPeak under the sample's own ramp params and the county
// cutoffs that were live when it trained.
func gradeScore(samples []wavePeakSample, shift float64) float64 {
	if len(samples) == 0 {
		return 0
	}
	var cost float64
	for _, s := range samples {
		hardOpen, hardClose := s.hardOpen, s.hardClose
		if hardClose <= 0 {
			hardOpen, hardClose = hardOpenFt, hardCloseFt
		}
		rp := RampParams{ThresholdFt: s.thresholdFt, CloseRate: s.closeRate}
		switch risk := riskForPeak(s.peakFt, shift, rp, hardOpen, hardClose); {
		case risk == RiskPossible && s.label:
			cost += costCovered
		case risk == RiskPossible:
			cost += costHedged
		case risk == RiskLikely && !s.label:
			cost += costFalseAlarm
		case risk == RiskNone && s.label:
			cost += costMiss
		}
	}
	return 1 - cost/(costMiss*float64(len(samples)))
}

// waveQuantile returns the q-quantile of the pool's wave heights.
func waveQuantile(sortedHeights []float64, q float64) float64 {
	return sortedHeights[int(q*float64(len(sortedHeights)-1))]
}

// bestRegime jointly scans boundary candidates (wave-height quantiles, so
// they rescale with any buoy) and shift magnitudes. sign is +1 for the calm
// raise, -1 for the rough drop; the returned shift is a magnitude.
//
// A candidate qualifies only when its shift beats shift-0 by minWaveGain
// *within its own regime* — the shift touches nothing else, and a
// regime-local bar stays meaningful whatever the pool size. Among
// qualifying candidates, the winner is the one fixing the most weighted
// pool error (regime improvement × regime weight). No qualifier → the
// fallback-quantile boundary and shift 0, i.e. tide-only behavior.
func bestRegime(pooled []wavePeakSample, sortedHeights []float64, quantiles []float64, fallbackQ, sign float64) (boundary, shift float64) {
	calmSide := sign > 0
	boundary = waveQuantile(sortedHeights, fallbackQ)
	bestShift, bestFixed := 0.0, 0.0

	for _, q := range quantiles {
		b := waveQuantile(sortedHeights, q)
		var regime []wavePeakSample
		var regimeWeight float64
		for _, s := range pooled {
			if (calmSide && s.waveFt <= b) || (!calmSide && s.waveFt >= b) {
				regime = append(regime, s)
				if s.label {
					regimeWeight += closedPeakWeight
				} else {
					regimeWeight++
				}
			}
		}
		if len(regime) < minWaveRegimeSamples {
			continue
		}
		base := gradeScore(regime, 0)
		for mag := waveShiftStepFt; mag <= maxWaveShiftFt+1e-9; mag += waveShiftStepFt {
			gain := gradeScore(regime, sign*mag) - base
			if gain < minWaveGain {
				continue
			}
			if fixed := gain * regimeWeight; fixed > bestFixed {
				bestFixed = fixed
				boundary, bestShift = b, mag
			}
		}
	}
	if bestShift == 0 {
		return waveQuantile(sortedHeights, fallbackQ), 0
	}
	return boundary, math.Round(bestShift*100) / 100
}

// persistSample is one labeled daytime peak with what its ramp did the
// previous Eastern day — the unit the persistence prior trains on. Peaks
// whose prior day is unknown (first day of history, no daytime peak, peak
// under the hard-open cutoff) are left out.
type persistSample struct {
	wavePeakSample
	priorClosed bool
}

// bestPersistShift scans shift magnitudes in one direction (sign +1 raises
// the bar, -1 lowers it) over one side's samples, returning the magnitude
// that most improves weighted accuracy over shift 0 — or 0 when nothing
// beats it by minPersistGain. Same idiom as bestRegime, minus the boundary.
func bestPersistShift(side []wavePeakSample, sign float64) float64 {
	if len(side) < minPersistSideSamples {
		return 0
	}
	base := gradeScore(side, 0)
	best, bestGain := 0.0, minPersistGain
	for mag := waveShiftStepFt; mag <= maxPersistShiftFt+1e-9; mag += waveShiftStepFt {
		if gain := gradeScore(side, sign*mag) - base; gain >= bestGain {
			best, bestGain = mag, gain
		}
	}
	return math.Round(best*100) / 100
}

// trainPersistParams learns the one-day persistence prior from the pooled
// peaks: one shift for peaks whose ramp rode out yesterday's tide, one for
// peaks whose ramp closed. Each side is scanned independently, because the
// two are different questions (the data says the open side carries most of
// the signal). Returns nil when the pool is too thin, which serves as the
// memoryless model.
func trainPersistParams(pool []persistSample) *PersistenceParams {
	if len(pool) < minPersistPoolSamples {
		return nil
	}
	return persistParamsFor(pool)
}

// persistParamsFor scans both sides of an already-large-enough pool.
func persistParamsFor(pool []persistSample) *PersistenceParams {
	var open, closed []wavePeakSample
	for _, s := range pool {
		if s.priorClosed {
			closed = append(closed, s.wavePeakSample)
		} else {
			open = append(open, s.wavePeakSample)
		}
	}
	pp := &PersistenceParams{
		OpenRaiseFt:  bestPersistShift(open, 1),
		ClosedDropFt: bestPersistShift(closed, -1),
		NSamples:     len(pool),
	}
	if pp.OpenRaiseFt == 0 && pp.ClosedDropFt == 0 {
		return nil
	}
	// Pooled grade score with both shifts applied, for the admin view.
	pp.Accuracy = math.Round((gradeScore(open, pp.OpenRaiseFt)*float64(len(open))+gradeScore(closed, -pp.ClosedDropFt)*float64(len(closed)))/float64(len(pool))*1000) / 1000
	return pp
}

// priorDayLabels maps each Eastern date to whether any of that day's
// labeled peaks closed — the per-ramp source of "did it close yesterday?"
// during training. Days whose max peak is at or under hardOpenFt are
// omitted (no evidence either way), matching priorDayFacts.
func priorDayLabels(peaks []models.TidePrediction, labels []bool, hardOpenFt float64) map[string]bool {
	closedByDay := make(map[string]bool)
	maxByDay := make(map[string]float64)
	for i, p := range peaks {
		d := p.Time.In(eastern).Format("2006-01-02")
		closedByDay[d] = closedByDay[d] || labels[i]
		if *p.Height > maxByDay[d] {
			maxByDay[d] = *p.Height
		}
	}
	for d, m := range maxByDay {
		if m <= hardOpenFt {
			delete(closedByDay, d)
		}
	}
	return closedByDay
}

// trainWaveParams learns the county-wide calm/rough regime split from the
// pooled wave-matched peaks: for each side, the boundary (scanned over
// wave-height quantiles) and the threshold shift are chosen jointly to
// maximize whole-pool label accuracy — the same closed-form idiom as
// bestThreshold. Returns nil when the pool is too thin to trust, which
// downstream reads as "tide-only".
func trainWaveParams(pooled []wavePeakSample) *WaveParams {
	if len(pooled) < minWavePoolSamples {
		return nil
	}

	heights := make([]float64, len(pooled))
	for i, s := range pooled {
		heights[i] = s.waveFt
	}
	sort.Float64s(heights)

	// Candidate quantiles keep each regime a real minority share of days —
	// a "calm" that covers most of the summer stops meaning anything.
	calmQs := []float64{0.20, 0.25, 0.30, 0.35, 0.40, 0.45, 0.50}
	roughQs := []float64{0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.90}

	calmMax, calmRaise := bestRegime(pooled, heights, calmQs, 0.30, 1)
	roughMin, roughDrop := bestRegime(pooled, heights, roughQs, 0.75, -1)

	// The regimes may not cross: an overlapping pick would double-shift
	// nothing (waveShift checks calm first) but read as nonsense in the
	// admin view. Keep the calm side — suppression is the better-evidenced
	// signal — and disable the rough shift.
	if roughMin <= calmMax {
		roughMin = waveQuantile(heights, 0.75)
		roughDrop = 0
	}

	// Boundaries round outward (calm up, rough down) so the observations
	// that defined each quantile stay inside their own regime.
	wp := &WaveParams{
		CalmMaxFt:   math.Ceil(calmMax*100) / 100,
		RoughMinFt:  math.Floor(roughMin*100) / 100,
		CalmRaiseFt: calmRaise,
		RoughDropFt: roughDrop,
		NSamples:    len(pooled),
	}

	// Pooled grade score with both learned shifts applied, for the admin view.
	var calm, rough, neutral []wavePeakSample
	for _, s := range pooled {
		switch {
		case s.waveFt <= calmMax:
			calm = append(calm, s)
		case s.waveFt >= roughMin:
			rough = append(rough, s)
		default:
			neutral = append(neutral, s)
		}
	}
	total := gradeScore(calm, wp.CalmRaiseFt)*float64(len(calm)) + gradeScore(rough, -wp.RoughDropFt)*float64(len(rough)) + gradeScore(neutral, 0)*float64(len(neutral))
	wp.Accuracy = math.Round(total/float64(len(pooled))*1000) / 1000

	return wp
}

// Train derives Params from full status-event history (per access_id,
// ascending), hilo tide predictions covering the same span, and the buoy
// wave series (any order; nil trains tide-only). excludedDays manually
// quarantines whole ET dates (ParseExcludedDays; nil is fine) on top of the
// automatic staleness heuristics.
func Train(historyByRamp map[string][]models.StatusEvent, preds []models.TidePrediction, waves []models.WaveSample, now time.Time, excludedDays map[string]bool) Params {
	peaks := tidePeaks(preds)
	sortWaveSamples(waves)
	excl := findExclusions(historyByRamp, now, excludedDays)

	params := Params{
		Version:    paramsVersion,
		ComputedAt: now.UTC(),
		Default:    DefaultParams,
		Ramps:      make(map[string]RampParams),
	}

	// County-wide hard cutoffs from the peak distribution (see Params).
	// P05/P97 reproduce the original 2.0/3.5 ft analysis on station 8721147
	// and rescale automatically on any other configured station.
	if len(peaks) >= 40 {
		params.HardOpenFt = math.Round(peakQuantile(peaks, 0.05)*100) / 100
		params.HardCloseFt = math.Round(peakQuantile(peaks, 0.97)*100) / 100
	}

	// How early (or late) the county actually clears the beach relative to
	// the posted close — the outlook predicts what they do, not what is
	// posted.
	if offsets := dayCloseOffsets(historyByRamp); len(offsets) >= minDayCloseSamples {
		params.DayCloseOffsetMin = int(math.Round(median(offsets)))
	}

	var historyStart time.Time
	var thresholds, leads, lags []float64
	var wavePool []wavePeakSample
	var persistPool []persistSample

	for accessID, events := range historyByRamp {
		if len(events) == 0 {
			continue
		}
		if historyStart.IsZero() || events[0].RecordedAt.Before(historyStart) {
			historyStart = events[0].RecordedAt
		}

		closures := closureEvents(events)
		if len(closures) < minClosuresForRamp {
			continue
		}

		// Only peaks inside this ramp's observed history are labelable, and
		// peaks on quarantined stale days carry no evidence at all — dropping
		// them here cleanses every downstream pool (labels, threshold, close
		// rate, wave regimes, persistence pairs) in one place.
		var rampPeaks []models.TidePrediction
		for _, p := range peaks {
			if p.Time.After(events[0].RecordedAt) && p.Time.Before(now) && !excl.excluded(accessID, p.Time) {
				rampPeaks = append(rampPeaks, p)
			}
		}
		if len(rampPeaks) == 0 {
			continue
		}

		labels := labelPeaks(rampPeaks, closures)
		var nClosed int
		for _, l := range labels {
			if l {
				nClosed++
			}
		}
		threshold, accuracy := bestThreshold(rampPeaks, labels)
		lead, lag, matched := leadLag(rampPeaks, closures)
		if matched < minClosuresForRamp {
			continue
		}
		if lead <= 0 {
			lead = DefaultParams.LeadMin
		}
		if lag <= 0 {
			lag = DefaultParams.LagMin
		}

		closeRate := math.Round(float64(nClosed)/float64(len(labels))*1000) / 1000
		params.Ramps[accessID] = RampParams{
			ThresholdFt: threshold,
			Accuracy:    accuracy,
			NClosures:   len(closures),
			CloseRate:   closeRate,
			LeadMin:     lead,
			LagMin:      lag,
		}
		thresholds = append(thresholds, threshold)
		leads = append(leads, float64(lead))
		lags = append(lags, float64(lag))

		// Pool this ramp's peaks for the persistence prior: each peak with
		// what the ramp did the previous day, when that day is known. The
		// ramp learns its own shifts when it has enough pairs on both
		// sides; otherwise it falls back to the county-wide pool below.
		byDay := priorDayLabels(rampPeaks, labels, params.hardOpen())
		var rampPool []persistSample
		nPriorClosed := 0
		for i, p := range rampPeaks {
			prev := p.Time.In(eastern).AddDate(0, 0, -1).Format("2006-01-02")
			if closed, ok := byDay[prev]; ok {
				rampPool = append(rampPool, persistSample{
					wavePeakSample: wavePeakSample{
						peakFt: *p.Height, thresholdFt: threshold, closeRate: closeRate, label: labels[i],
						hardOpen: params.hardOpen(), hardClose: params.hardClose(),
					},
					priorClosed: closed,
				})
				if closed {
					nPriorClosed++
				}
			}
		}
		persistPool = append(persistPool, rampPool...)
		if nPriorClosed >= minPersistSideSamples && len(rampPool)-nPriorClosed >= minPersistSideSamples {
			rp := params.Ramps[accessID]
			rp.Persistence = persistParamsFor(rampPool)
			params.Ramps[accessID] = rp
		}

		// Pool this ramp's peaks for the county-wide wave regime split —
		// only peaks with a nearby buoy observation; outage gaps still train
		// the tide thresholds above.
		for i, p := range rampPeaks {
			if w := waveNearTime(waves, p.Time); w != nil {
				wavePool = append(wavePool, wavePeakSample{
					peakFt: *p.Height, thresholdFt: threshold, closeRate: closeRate, label: labels[i],
					waveFt: w.HeightFt, hardOpen: params.hardOpen(), hardClose: params.hardClose(),
				})
			}
		}
	}

	if !historyStart.IsZero() {
		params.HistoryStart = historyStart.In(eastern).Format("2006-01-02")
	}

	// County default: medians across learned ramps once enough exist.
	if len(thresholds) >= 3 {
		params.Default = RampParams{
			ThresholdFt: math.Round(median(thresholds)*100) / 100,
			LeadMin:     int(math.Round(median(leads))),
			LagMin:      int(math.Round(median(lags))),
		}
	}

	params.Waves = trainWaveParams(wavePool)
	params.Persistence = trainPersistParams(persistPool)

	return params
}

var eastern *time.Location

func init() {
	var err error
	eastern, err = time.LoadLocation("America/New_York")
	if err != nil {
		panic(fmt.Sprintf("failed to load America/New_York timezone: %v", err))
	}
}
