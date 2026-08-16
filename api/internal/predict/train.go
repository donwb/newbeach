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

	// Threshold candidates are scanned over this clamped range (ft MLLW).
	minThresholdFt = 1.5
	maxThresholdFt = 4.5
)

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

	best := DefaultParams.ThresholdFt
	bestAcc := -1.0
	total := float64(len(labels))
	for th := minThresholdFt; th <= maxThresholdFt+1e-9; th += 0.05 {
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

// Train derives Params from full status-event history (per access_id,
// ascending) and hilo tide predictions covering the same span.
func Train(historyByRamp map[string][]models.StatusEvent, preds []models.TidePrediction, now time.Time) Params {
	peaks := tidePeaks(preds)

	params := Params{
		Version:    paramsVersion,
		ComputedAt: now.UTC(),
		Default:    DefaultParams,
		Ramps:      make(map[string]RampParams),
	}

	var historyStart time.Time
	var thresholds, leads, lags []float64

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

		// Only peaks inside this ramp's observed history are labelable.
		var rampPeaks []models.TidePrediction
		for _, p := range peaks {
			if p.Time.After(events[0].RecordedAt) && p.Time.Before(now) {
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

		params.Ramps[accessID] = RampParams{
			ThresholdFt: threshold,
			Accuracy:    accuracy,
			NClosures:   len(closures),
			CloseRate:   math.Round(float64(nClosed)/float64(len(labels))*1000) / 1000,
			LeadMin:     lead,
			LagMin:      lag,
		}
		thresholds = append(thresholds, threshold)
		leads = append(leads, float64(lead))
		lags = append(lags, float64(lag))
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
