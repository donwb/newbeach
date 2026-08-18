package predict

import (
	"sort"
	"time"

	"github.com/donwb/beach/api/internal/models"
)

// maxWaveMatchGap bounds how far a wave observation can sit from a tide peak
// (or a serve moment) and still describe its sea state. Buoy 41113 reports
// every 30 minutes, so 3 hours only comes into play across outage gaps.
const maxWaveMatchGap = 3 * time.Hour

// waveNearTime returns the sample nearest t within maxWaveMatchGap, or nil.
// samples must be ascending by time (sortWaveSamples arranges that).
func waveNearTime(samples []models.WaveSample, t time.Time) *models.WaveSample {
	if len(samples) == 0 {
		return nil
	}
	i := sort.Search(len(samples), func(i int) bool {
		return !samples[i].Time.Before(t)
	})

	best := -1
	bestGap := maxWaveMatchGap
	for _, j := range []int{i - 1, i} {
		if j < 0 || j >= len(samples) {
			continue
		}
		gap := samples[j].Time.Sub(t)
		if gap < 0 {
			gap = -gap
		}
		if gap <= bestGap {
			bestGap = gap
			best = j
		}
	}
	if best < 0 {
		return nil
	}
	return &samples[best]
}

// sortWaveSamples sorts samples ascending by time, in place — the order
// waveNearTime requires. NDBC realtime2 files arrive newest-first.
func sortWaveSamples(samples []models.WaveSample) {
	sort.Slice(samples, func(i, j int) bool {
		return samples[i].Time.Before(samples[j].Time)
	})
}
