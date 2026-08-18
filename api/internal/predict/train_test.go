package predict

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/donwb/beach/api/internal/models"
)

// et builds an Eastern-time instant on a given 2026 summer day.
func et(day, hour, min int) time.Time {
	return time.Date(2026, 6, day, hour, min, 0, 0, eastern)
}

func h(t time.Time, height float64) models.TidePrediction {
	return models.TidePrediction{Time: t, Type: "H", Height: &height}
}

func TestClosureEvents(t *testing.T) {
	events := []models.StatusEvent{
		{AccessStatus: "OPEN", RecordedAt: et(1, 8, 0)},
		{AccessStatus: "CLOSED FOR HIGH TIDE", RecordedAt: et(1, 12, 0)},
		{AccessStatus: "OPEN", RecordedAt: et(1, 15, 0)},
		{AccessStatus: "CLOSED FOR HIGH TIDE", RecordedAt: et(2, 13, 0)},
		// no reopen for the second closure — still closed at history end
	}

	closures := closureEvents(events)
	require.Len(t, closures, 2)
	assert.Equal(t, et(1, 12, 0), closures[0].closedAt)
	assert.Equal(t, et(1, 15, 0), closures[0].reopenedAt)
	assert.Equal(t, et(2, 13, 0), closures[1].closedAt)
	assert.True(t, closures[1].reopenedAt.IsZero())
}

func TestTidePeaksFiltersOvernightAndLows(t *testing.T) {
	low := 0.5
	preds := []models.TidePrediction{
		h(et(1, 14, 0), 3.0),                         // daytime high — kept
		h(et(1, 2, 0), 3.5),                          // overnight high — dropped
		{Time: et(1, 8, 0), Type: "L", Height: &low}, // low — dropped
		{Time: et(1, 15, 0), Type: "H", Height: nil}, // no height — dropped
	}
	peaks := tidePeaks(preds)
	require.Len(t, peaks, 1)
	assert.Equal(t, et(1, 14, 0), peaks[0].Time)
}

// buildSeparableHistory produces a ramp that closes around every peak >= cut
// and stays open otherwise, with closures starting 90 minutes before the
// peak and reopening 60 minutes after.
func buildSeparableHistory(peaks []models.TidePrediction, cut float64) []models.StatusEvent {
	events := []models.StatusEvent{{AccessStatus: "OPEN", RecordedAt: et(1, 6, 0)}}
	for _, p := range peaks {
		if *p.Height >= cut {
			events = append(events,
				models.StatusEvent{AccessStatus: "CLOSED FOR HIGH TIDE", RecordedAt: p.Time.Add(-90 * time.Minute)},
				models.StatusEvent{AccessStatus: "OPEN", RecordedAt: p.Time.Add(60 * time.Minute)},
			)
		}
	}
	return events
}

func TestTrainLearnsSeparableThreshold(t *testing.T) {
	// 14 daytime peaks alternating clearly below/above a 2.8 ft cut.
	var peaks []models.TidePrediction
	for day := 1; day <= 14; day++ {
		height := 2.2
		if day%2 == 0 {
			height = 3.2
		}
		peaks = append(peaks, h(et(day, 13, 0), height))
	}

	history := map[string][]models.StatusEvent{
		"NS-999": buildSeparableHistory(peaks, 2.8),
	}

	params := Train(history, peaks, nil, et(15, 0, 0))

	rp, ok := params.Ramps["NS-999"]
	require.True(t, ok, "ramp should earn learned params")
	assert.Equal(t, 7, rp.NClosures)
	assert.InDelta(t, 1.0, rp.Accuracy, 0.001, "perfectly separable data")
	assert.Greater(t, rp.ThresholdFt, 2.2)
	assert.LessOrEqual(t, rp.ThresholdFt, 3.2)
	assert.Equal(t, 90, rp.LeadMin)
	assert.Equal(t, 60, rp.LagMin)
}

func TestTrainSkipsSmallSamples(t *testing.T) {
	peaks := []models.TidePrediction{h(et(1, 13, 0), 3.0), h(et(2, 13, 0), 3.1)}
	history := map[string][]models.StatusEvent{
		"PI-001": buildSeparableHistory(peaks, 2.8), // only 2 closures
	}

	params := Train(history, peaks, nil, et(3, 0, 0))
	_, ok := params.Ramps["PI-001"]
	assert.False(t, ok, "under-sampled ramp falls back to default")
	assert.Equal(t, DefaultParams, params.Default, "defaults survive with <3 learned ramps")
}

func TestTrainNoisyDataStillReasonable(t *testing.T) {
	// Mostly separable at 2.8, with two label flips.
	var peaks []models.TidePrediction
	for day := 1; day <= 20; day++ {
		height := 2.2
		if day%2 == 0 {
			height = 3.2
		}
		peaks = append(peaks, h(et(day, 13, 0), height))
	}
	cut := 2.8
	events := buildSeparableHistory(peaks, cut)
	// Noise: a closure on a low day.
	events = append(events,
		models.StatusEvent{AccessStatus: "CLOSED FOR HIGH TIDE", RecordedAt: et(1, 12, 0)},
		models.StatusEvent{AccessStatus: "OPEN", RecordedAt: et(1, 14, 30)},
	)

	params := Train(map[string][]models.StatusEvent{"DB-001": events}, peaks, nil, et(21, 0, 0))
	rp, ok := params.Ramps["DB-001"]
	require.True(t, ok)
	assert.Greater(t, rp.Accuracy, 0.85, "one flipped label barely dents balanced accuracy")
	assert.InDelta(t, 2.8, rp.ThresholdFt, 0.65)
}

func TestMedian(t *testing.T) {
	assert.Equal(t, 0.0, median(nil))
	assert.Equal(t, 5.0, median([]float64{5}))
	assert.Equal(t, 2.5, median([]float64{1, 4, 2, 3}))
	assert.Equal(t, 3.0, median([]float64{5, 1, 3}))
}

func TestNextRunTime(t *testing.T) {
	beforeRun := time.Date(2026, 8, 16, 2, 0, 0, 0, eastern)
	assert.Equal(t, time.Date(2026, 8, 16, 3, 30, 0, 0, eastern), nextRunTime(beforeRun))

	afterRun := time.Date(2026, 8, 16, 4, 0, 0, 0, eastern)
	assert.Equal(t, time.Date(2026, 8, 17, 3, 30, 0, 0, eastern), nextRunTime(afterRun))
}
