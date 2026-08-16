package solar

import (
	"math"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// summerDay is 2026-06-18 18:00 UTC — the same reference instant used by
// SolarCalculatorTests.swift so all three ports agree on expected values.
var summerDay = time.Date(2026, 6, 18, 18, 0, 0, 0, time.UTC)

func TestEventsSummerDay(t *testing.T) {
	sunrise, sunset := Events(summerDay, NSB)
	require.NotNil(t, sunrise)
	require.NotNil(t, sunset)

	assert.True(t, sunrise.Before(*sunset), "sunrise before sunset")

	// NSB in mid-June: sunrise ~6:25 AM ET, sunset ~8:25 PM ET.
	assert.Equal(t, 6, sunrise.In(eastern).Hour())
	assert.Equal(t, 20, sunset.In(eastern).Hour())

	// At sunrise the sun sits at the standard horizon altitude (-0.833°).
	assert.InDelta(t, HorizonAltitude, Altitude(*sunrise, NSB), 0.05)
	assert.InDelta(t, HorizonAltitude, Altitude(*sunset, NSB), 0.05)
}

func TestAltitude(t *testing.T) {
	noon := time.Date(2026, 6, 18, 13, 0, 0, 0, eastern)
	assert.Greater(t, Altitude(noon, NSB), 60.0, "sun high overhead just after solar noon")

	midnight := time.Date(2026, 6, 18, 0, 0, 0, 0, eastern)
	assert.Less(t, Altitude(midnight, NSB), 0.0, "sun below horizon at midnight")
}

func TestEventsWinterDayShorter(t *testing.T) {
	winterDay := time.Date(2026, 12, 18, 18, 0, 0, 0, time.UTC)

	wRise, wSet := Events(winterDay, NSB)
	require.NotNil(t, wRise)
	require.NotNil(t, wSet)
	sRise, sSet := Events(summerDay, NSB)

	winterLen := wSet.Sub(*wRise)
	summerLen := sSet.Sub(*sRise)
	assert.Less(t, winterLen, summerLen, "winter days are shorter")
	// Sanity: NSB winter daylight is roughly 10.3h, summer roughly 14h.
	assert.InDelta(t, 10.3, winterLen.Hours(), 0.5)
	assert.InDelta(t, 14.0, summerLen.Hours(), 0.5)
}

func TestEventsAcrossDSTTransition(t *testing.T) {
	// 2026-11-01 is the fall-back day (25-hour Eastern day); events must
	// still produce a coherent sunrise/sunset pair.
	fallBack := time.Date(2026, 11, 1, 17, 0, 0, 0, time.UTC)
	sunrise, sunset := Events(fallBack, NSB)
	require.NotNil(t, sunrise)
	require.NotNil(t, sunset)
	assert.True(t, sunrise.Before(*sunset))
	// Post-fall-back sunset in NSB is ~5:40 PM ET.
	assert.Equal(t, 17, sunset.In(eastern).Hour())
}

func TestNormalizeDegrees(t *testing.T) {
	assert.InDelta(t, 10.0, normalizeDegrees(370), 1e-9)
	assert.InDelta(t, 350.0, normalizeDegrees(-10), 1e-9)
	assert.InDelta(t, 0.0, math.Min(normalizeDegrees(720), 1e-12), 1e-9)
}
