// Package solar computes sun position for a fixed location. Direct port of
// web/js/solar.js (itself a port of the shared Swift package's
// SolarCalculator) — a low-precision NOAA-style model, good to a fraction of
// a degree. Pure functions; day boundaries are evaluated in Eastern time to
// match the JS and Swift implementations.
package solar

import (
	"fmt"
	"math"
	"time"
)

// Location is a geographic point.
type Location struct {
	Latitude  float64
	Longitude float64
}

// NSB is New Smyrna Beach, FL — the location the app is anchored to.
var NSB = Location{Latitude: 29.0258, Longitude: -80.927}

// HorizonAltitude is the standard sunrise/sunset altitude: −0.833° accounts
// for the sun's apparent radius plus atmospheric refraction at the horizon.
const HorizonAltitude = -0.833

const stepMs = 300_000 // 5-minute coarse scan, refined by bisection

var eastern *time.Location

func init() {
	var err error
	eastern, err = time.LoadLocation("America/New_York")
	if err != nil {
		panic(fmt.Sprintf("failed to load America/New_York timezone: %v", err))
	}
}

func rad(d float64) float64 { return d * math.Pi / 180 }
func deg(r float64) float64 { return r * 180 / math.Pi }

func normalizeDegrees(value float64) float64 {
	r := math.Mod(value, 360)
	if r < 0 {
		r += 360
	}
	return r
}

// Altitude returns the sun's altitude above the horizon, in degrees, at the
// given instant. Negative means below the horizon (twilight or night).
func Altitude(t time.Time, loc Location) float64 {
	julian := float64(t.UnixMilli())/86_400_000 + 2_440_587.5
	n := julian - 2_451_545.0 // days since J2000.0

	meanLongitude := normalizeDegrees(280.46 + 0.9856474*n)
	meanAnomaly := normalizeDegrees(357.528 + 0.9856003*n)
	eclipticLongitude := meanLongitude +
		1.915*math.Sin(rad(meanAnomaly)) +
		0.02*math.Sin(rad(2*meanAnomaly))
	obliquity := 23.439 - 0.0000004*n

	declination := math.Asin(math.Sin(rad(obliquity)) * math.Sin(rad(eclipticLongitude)))
	rightAscension := math.Atan2(
		math.Cos(rad(obliquity))*math.Sin(rad(eclipticLongitude)),
		math.Cos(rad(eclipticLongitude)),
	)

	gmst := normalizeDegrees(280.46061837 + 360.98564736629*n)
	localSiderealTime := rad(gmst + loc.Longitude)
	hourAngle := localSiderealTime - rightAscension

	lat := rad(loc.Latitude)
	sinAltitude := math.Sin(lat)*math.Sin(declination) +
		math.Cos(lat)*math.Cos(declination)*math.Cos(hourAngle)
	return deg(math.Asin(math.Min(1, math.Max(-1, sinAltitude))))
}

// easternMidnight returns the start of the Eastern calendar day containing t.
func easternMidnight(t time.Time) time.Time {
	et := t.In(eastern)
	return time.Date(et.Year(), et.Month(), et.Day(), 0, 0, 0, 0, eastern)
}

func refineCrossing(from, to time.Time, target float64, rising bool, loc Location) time.Time {
	low := float64(from.UnixMilli())
	high := float64(to.UnixMilli())
	for i := 0; i < 24; i++ {
		mid := low + (high-low)/2
		above := Altitude(time.UnixMilli(int64(mid)), loc) >= target
		if above == rising {
			high = mid
		} else {
			low = mid
		}
	}
	return time.UnixMilli(int64(low + (high-low)/2))
}

// Events returns sunrise and sunset for the Eastern calendar day containing
// t. Either may be nil if no crossing occurs that day.
func Events(t time.Time, loc Location) (sunrise, sunset *time.Time) {
	startOfDay := easternMidnight(t)

	prevTime := startOfDay
	prevAltitude := Altitude(startOfDay, loc)
	for offset := int64(stepMs); offset <= 86_400_000; offset += stepMs {
		cur := startOfDay.Add(time.Duration(offset) * time.Millisecond)
		alt := Altitude(cur, loc)

		if sunrise == nil && prevAltitude < HorizonAltitude && alt >= HorizonAltitude {
			r := refineCrossing(prevTime, cur, HorizonAltitude, true, loc)
			sunrise = &r
		}
		if sunset == nil && prevAltitude >= HorizonAltitude && alt < HorizonAltitude {
			s := refineCrossing(prevTime, cur, HorizonAltitude, false, loc)
			sunset = &s
		}

		prevTime = cur
		prevAltitude = alt
	}
	return sunrise, sunset
}
