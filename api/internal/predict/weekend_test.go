package predict

import (
	"encoding/json"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/donwb/beach/api/internal/models"
	"github.com/donwb/beach/api/internal/nwsfc"
)

// --- test scaffolding ---

func etTime(t *testing.T, s string) time.Time {
	t.Helper()
	tt, err := time.ParseInLocation("2006-01-02 15:04", s, eastern)
	require.NoError(t, err)
	return tt
}

func highAt(t *testing.T, s string, ft float64) models.TidePrediction {
	t.Helper()
	return models.TidePrediction{Time: etTime(t, s), Type: "H", Height: &ft}
}

func testRamps() []models.RampStatusWithSince {
	names := map[string]string{"NS-141": "3rd Ave", "NS-118": "Crawford", "DB-041": "Silver Beach"}
	var ramps []models.RampStatusWithSince
	for id, name := range names {
		n := name
		r := models.RampStatusWithSince{ShortName: &n}
		r.AccessID = id
		r.AccessStatus = "OPEN"
		ramps = append(ramps, r)
	}
	return ramps
}

func weekendTestParams() Params {
	return Params{Default: DefaultParams}
}

// flatLand builds an hourly land forecast covering [from, to) with the given
// per-hour template, optionally mutated by hook(hourUTC, sample).
func flatLand(from, to time.Time, hook func(time.Time, *nwsfc.HourlySample)) *nwsfc.LandForecast {
	lf := &nwsfc.LandForecast{FetchedAt: from}
	for t := from.UTC().Truncate(time.Hour); t.Before(to.UTC()); t = t.Add(time.Hour) {
		temp, pop, thunder, wind, gust := 90.0, 20.0, 10.0, 8.0, 12.0
		h := nwsfc.HourlySample{Time: t, TempF: &temp, PoPPct: &pop, ThunderPct: &thunder, WindMph: &wind, GustMph: &gust}
		if hook != nil {
			hook(t, &h)
		}
		lf.Hours = append(lf.Hours, h)
	}
	return lf
}

// quietWeek is a benign midweek baseline: Wednesday 10am ET in August
// (turtle season), calm 2.0 ft peaks every day, pleasant weather for 6 days.
func quietWeek(t *testing.T) (time.Time, []models.TidePrediction, *nwsfc.LandForecast) {
	t.Helper()
	now := etTime(t, "2026-08-19 10:00") // Wednesday
	var preds []models.TidePrediction
	for d := 0; d < 8; d++ {
		day := now.AddDate(0, 0, d)
		preds = append(preds, highAt(t, day.Format("2006-01-02")+" 13:00", 2.0))
	}
	land := flatLand(now, now.AddDate(0, 0, 7), nil)
	return now, preds, land
}

func day(t *testing.T, out WeekendOutlook, weekday string) *WeekendDay {
	t.Helper()
	for i := range out.Days {
		if out.Days[i].Weekday == weekday {
			return &out.Days[i]
		}
	}
	return nil
}

// --- scenarios ---

func TestWeekendMidweekHorizon(t *testing.T) {
	now, preds, land := quietWeek(t)
	out := BuildWeekendOutlook(now, testRamps(), weekendTestParams(), DefaultVerdictParams(), preds, land, nil)

	require.Len(t, out.Days, 7)
	assert.Equal(t, "2026-08-19", out.Days[0].Date, "today stays in the list while its driving day is live")
	assert.Equal(t, "Wednesday", out.Days[0].Weekday)

	sat, sun := day(t, out, "Saturday"), day(t, out, "Sunday")
	require.NotNil(t, sat)
	require.NotNil(t, sun)
	assert.True(t, sat.IsWeekend)
	assert.True(t, sun.IsWeekend)
	for _, d := range out.Days {
		if d.Weekday != "Saturday" && d.Weekday != "Sunday" {
			assert.False(t, d.IsWeekend, d.Weekday)
		}
	}

	// Quiet week: everything covered by weather reads great, pressure none.
	for _, d := range out.Days {
		assert.Equal(t, PressureNone, d.ClosurePressure, d.Weekday)
		assert.Contains(t, d.Basis, "weather", d.Weekday)
		assert.Equal(t, VerdictGreat, d.Verdict, d.Weekday)
		assert.NotNil(t, d.HighTempF, d.Weekday)
	}
	assert.NotEmpty(t, out.Headline)
}

func TestWeekendSaturdayAfternoonAndRollover(t *testing.T) {
	_, preds, _ := quietWeek(t)

	// Saturday 3pm: today leads the list, clamped to the remaining day.
	satPM := etTime(t, "2026-08-22 15:00")
	land := flatLand(satPM, satPM.AddDate(0, 0, 7), nil)
	out := BuildWeekendOutlook(satPM, testRamps(), weekendTestParams(), DefaultVerdictParams(), preds, land, nil)
	require.NotEmpty(t, out.Days)
	assert.Equal(t, "Saturday", out.Days[0].Weekday)

	// Saturday 9pm: driving day is over — Sunday leads.
	satNight := etTime(t, "2026-08-22 21:00")
	out = BuildWeekendOutlook(satNight, testRamps(), weekendTestParams(), DefaultVerdictParams(), preds, land, nil)
	require.NotEmpty(t, out.Days)
	assert.Equal(t, "Sunday", out.Days[0].Weekday)
}

func TestWeekendTideOnlyDegradation(t *testing.T) {
	now, preds, _ := quietWeek(t)
	out := BuildWeekendOutlook(now, testRamps(), weekendTestParams(), DefaultVerdictParams(), preds, nil, nil)

	for _, d := range out.Days {
		assert.Equal(t, []string{"tide"}, d.Basis, d.Weekday)
		assert.Equal(t, VerdictGood, d.Verdict, "tide-only can't promise great")
		assert.Contains(t, d.Headline, "No weather call", d.Weekday)
		assert.Nil(t, d.HighTempF)
	}
}

func TestWeekendStormAfternoonStaysGoodWithMorningWindow(t *testing.T) {
	// The calibration rule: storms are timing, not probability. An afternoon
	// storm block must NOT sink the day — it shapes the window.
	now, preds, _ := quietWeek(t)
	stormStartET := 14 // 2pm ET

	land := flatLand(now, now.AddDate(0, 0, 7), func(tm time.Time, h *nwsfc.HourlySample) {
		if tm.In(eastern).Hour() >= stormStartET {
			v := 70.0
			h.ThunderPct = &v
		}
	})
	out := BuildWeekendOutlook(now, testRamps(), weekendTestParams(), DefaultVerdictParams(), preds, land, nil)

	sat := day(t, out, "Saturday")
	require.NotNil(t, sat)
	assert.Equal(t, VerdictGood, sat.Verdict, "afternoon storms must not cap below good")
	require.NotNil(t, sat.BestWindow, "storm afternoon should yield a morning window")
	assert.Equal(t, 8, sat.BestWindow.Start.In(eastern).Hour(), "window starts at the open")
	assert.LessOrEqual(t, sat.BestWindow.End.In(eastern).Hour(), stormStartET, "window ends before the storms")
	assert.Contains(t, strings.ToLower(sat.Headline+" "+sat.Detail), "storm")
}

func TestWeekendAllDayStormsCapMixed(t *testing.T) {
	now, preds, _ := quietWeek(t)
	land := flatLand(now, now.AddDate(0, 0, 7), func(tm time.Time, h *nwsfc.HourlySample) {
		v := 80.0
		h.ThunderPct = &v
	})
	out := BuildWeekendOutlook(now, testRamps(), weekendTestParams(), DefaultVerdictParams(), preds, land, nil)

	sat := day(t, out, "Saturday")
	require.NotNil(t, sat)
	assert.Equal(t, VerdictMixed, sat.Verdict)
	assert.Contains(t, strings.ToLower(sat.Headline), "storm")
}

func TestWeekendHeatDowngradeNamesItself(t *testing.T) {
	// The real 2026-08-19/20 case: a watchable tide caps at good, afternoon
	// storms shape the window, and a 108° heat index takes the last notch to
	// mixed — but the headline talks storms. The pill must justify itself:
	// heat is the binding driver, so `why` names it with the number, and the
	// chip row gets the feels-like the air temp was hiding.
	now, _, _ := quietWeek(t)
	var preds []models.TidePrediction
	for d := 0; d < 8; d++ {
		day := now.AddDate(0, 0, d)
		preds = append(preds, highAt(t, day.Format("2006-01-02")+" 13:00", 2.5)) // possible, not likely
	}
	land := flatLand(now, now.AddDate(0, 0, 7), func(tm time.Time, h *nwsfc.HourlySample) {
		hi := 108.0
		h.HeatIndexF = &hi
		if tm.In(eastern).Hour() >= 18 { // storms at the edge of the day
			v := 70.0
			h.ThunderPct = &v
		}
	})
	out := BuildWeekendOutlook(now, testRamps(), weekendTestParams(), DefaultVerdictParams(), preds, land, nil)

	thu := day(t, out, "Thursday")
	require.NotNil(t, thu)
	assert.Equal(t, PressureSome, thu.ClosurePressure)
	assert.Equal(t, VerdictMixed, thu.Verdict)
	assert.Equal(t, []string{DriverHeat}, thu.Drivers, "heat took the binding notch")

	assert.Contains(t, thu.Why, "heat", "the pill's cause must be visible")
	assert.Contains(t, thu.Why, "110°", "heat comes with its (rounded) number")
	assert.NotContains(t, strings.ToLower(thu.Headline), "heat", "headline keeps the plan; why carries the justification")

	require.NotNil(t, thu.FeelsLikeF)
	assert.Equal(t, 108.0, *thu.FeelsLikeF)

	// The detail clause also carries the number now.
	assert.Contains(t, thu.Detail, "~110°")
}

func TestWeekendWhySilentWhenHeadlineCovers(t *testing.T) {
	// When the headline already names the binding driver, why must not
	// repeat it — an all-day-storm mixed day is explained by its headline.
	now, preds, _ := quietWeek(t)
	land := flatLand(now, now.AddDate(0, 0, 7), func(tm time.Time, h *nwsfc.HourlySample) {
		v := 80.0
		h.ThunderPct = &v
	})
	out := BuildWeekendOutlook(now, testRamps(), weekendTestParams(), DefaultVerdictParams(), preds, land, nil)

	sat := day(t, out, "Saturday")
	require.NotNil(t, sat)
	assert.Equal(t, VerdictMixed, sat.Verdict)
	assert.Equal(t, []string{DriverStorms}, sat.Drivers)
	assert.Empty(t, sat.Why, "headline already says storms")

	// Great days carry no drivers and no why.
	quiet := BuildWeekendOutlook(now, testRamps(), weekendTestParams(), DefaultVerdictParams(), preds, flatLand(now, now.AddDate(0, 0, 7), nil), nil)
	for _, d := range quiet.Days {
		assert.Equal(t, VerdictGreat, d.Verdict, d.Weekday)
		assert.Empty(t, d.Drivers, d.Weekday)
		assert.Empty(t, d.Why, d.Weekday)
	}
}

func TestWeekendGustsCapTough(t *testing.T) {
	now, preds, _ := quietWeek(t)
	land := flatLand(now, now.AddDate(0, 0, 7), func(tm time.Time, h *nwsfc.HourlySample) {
		w, g := 20.0, 30.0
		h.WindMph = &w
		h.GustMph = &g
	})
	out := BuildWeekendOutlook(now, testRamps(), weekendTestParams(), DefaultVerdictParams(), preds, land, nil)

	sat := day(t, out, "Saturday")
	require.NotNil(t, sat)
	assert.Equal(t, VerdictTough, sat.Verdict)
	assert.Contains(t, strings.ToLower(sat.Headline), "wind")
	assert.Equal(t, "gusty", sat.WindLabel)
}

func TestWeekendVerdictParamsOverride(t *testing.T) {
	// Same gusty forecast, but the tunable threshold raised past it: the
	// verdict recovers. This is the settings-blob knob working end to end.
	now, preds, _ := quietWeek(t)
	land := flatLand(now, now.AddDate(0, 0, 7), func(tm time.Time, h *nwsfc.HourlySample) {
		w, g := 10.0, 30.0
		h.WindMph = &w
		h.GustMph = &g
	})

	vp := DefaultVerdictParams()
	vp.GustToughMph = 40
	out := BuildWeekendOutlook(now, testRamps(), weekendTestParams(), vp, preds, land, nil)
	sat := day(t, out, "Saturday")
	require.NotNil(t, sat)
	assert.Equal(t, VerdictGreat, sat.Verdict, "raised gust threshold should clear the day")

	// And the blob round-trips: a partial JSON override keeps other defaults.
	fromJSON := DefaultVerdictParams()
	require.NoError(t, json.Unmarshal([]byte(`{"gust_tough_mph": 40}`), &fromJSON))
	assert.Equal(t, 40.0, fromJSON.GustToughMph)
	assert.Equal(t, DefaultVerdictParams().ThunderBlockPct, fromJSON.ThunderBlockPct)
}

func TestWeekendColdJanuaryDay(t *testing.T) {
	now := etTime(t, "2026-01-14 10:00") // Wednesday, standard season
	var preds []models.TidePrediction
	for d := 0; d < 8; d++ {
		day := now.AddDate(0, 0, d)
		preds = append(preds, highAt(t, day.Format("2006-01-02")+" 13:00", 2.0))
	}
	land := flatLand(now, now.AddDate(0, 0, 7), func(tm time.Time, h *nwsfc.HourlySample) {
		v := 55.0
		h.TempF = &v
	})
	out := BuildWeekendOutlook(now, testRamps(), weekendTestParams(), DefaultVerdictParams(), preds, land, nil)

	sat := day(t, out, "Saturday")
	require.NotNil(t, sat)
	assert.Equal(t, VerdictGood, sat.Verdict, "cold downgrades one notch from great")
	assert.Contains(t, sat.Headline, "walk")
	assert.Contains(t, sat.Detail, "55°")
}

func TestWeekendBigTideSaturday(t *testing.T) {
	now, preds, land := quietWeek(t)
	// Replace Saturday's peak with one at the hard-close cutoff.
	for i := range preds {
		if preds[i].Time.In(eastern).Weekday() == time.Saturday {
			big := 3.8
			preds[i].Height = &big
		}
	}
	out := BuildWeekendOutlook(now, testRamps(), weekendTestParams(), DefaultVerdictParams(), preds, land, nil)

	sat := day(t, out, "Saturday")
	require.NotNil(t, sat)
	assert.Equal(t, PressureHigh, sat.ClosurePressure)
	assert.Equal(t, VerdictMixed, sat.Verdict, "high pressure caps at mixed")
	assert.Contains(t, strings.ToLower(sat.Headline), "tide")
	assert.Contains(t, sat.Detail, "3rd Ave", "dicey ramps are named")

	// The other days stay untouched.
	sun := day(t, out, "Sunday")
	require.NotNil(t, sun)
	assert.Equal(t, PressureNone, sun.ClosurePressure)
	assert.Equal(t, VerdictGreat, sun.Verdict)
}

func TestForecastDayShiftGuards(t *testing.T) {
	params := weekendTestParams()
	params.Waves = &WaveParams{CalmMaxFt: 1.5, RoughMinFt: 3.0, CalmRaiseFt: 0.4, RoughDropFt: 0.5}
	ft := func(v float64) *float64 { return &v }

	assert.Equal(t, 0.0, forecastDayShift(params, nil, 1), "nil height")
	assert.Equal(t, 0.0, forecastDayShift(weekendTestParams(), ft(1.0), 1), "untrained waves")

	// Rough drop (hedging) always applies.
	assert.Equal(t, -0.5, forecastDayShift(params, ft(4.0), 5))

	// Calm raise (relaxing) only near-term and comfortably calm.
	assert.Equal(t, 0.4, forecastDayShift(params, ft(1.0), 2))
	assert.Equal(t, 0.0, forecastDayShift(params, ft(1.0), 4), "no calm relief past 3 days out")
	assert.Equal(t, 0.0, forecastDayShift(params, ft(1.3), 2), "not comfortably inside the calm regime")
}

// TestWeekendCopyRules sweeps every scenario's strings for voice violations:
// no promised closures, and clock times only on half-hour boundaries.
func TestWeekendCopyRules(t *testing.T) {
	minuteRe := regexp.MustCompile(`\d{1,2}:(\d{2})\s*(?:am|pm)`)

	checkDay := func(t *testing.T, d WeekendDay) {
		t.Helper()
		for _, s := range []string{d.Headline, d.Why, d.Detail} {
			lower := strings.ToLower(s)
			assert.NotContains(t, lower, "will close", "promised closure in %q", s)
			assert.NotContains(t, lower, "closure likely", "overconfident closure in %q", s)
			for _, m := range minuteRe.FindAllStringSubmatch(lower, -1) {
				assert.Equal(t, "30", m[1], "minute-precise time in %q", s)
			}
		}
		// The day's copy as a whole must name the tide when it's the pressure.
		if d.ClosurePressure != PressureNone {
			combined := strings.ToLower(d.Headline + " " + d.Detail)
			assert.Contains(t, combined, "tide", "tide pressure unnamed in %q / %q", d.Headline, d.Detail)
		}
	}

	now, preds, land := quietWeek(t)
	scenarios := []WeekendOutlook{
		BuildWeekendOutlook(now, testRamps(), weekendTestParams(), DefaultVerdictParams(), preds, land, nil),
		BuildWeekendOutlook(now, testRamps(), weekendTestParams(), DefaultVerdictParams(), preds, nil, nil),
	}
	// Big tide + storms together.
	for i := range preds {
		big := 3.8
		preds[i].Height = &big
	}
	stormy := flatLand(now, now.AddDate(0, 0, 7), func(tm time.Time, h *nwsfc.HourlySample) {
		v := 70.0
		h.ThunderPct = &v
	})
	scenarios = append(scenarios, BuildWeekendOutlook(now, testRamps(), weekendTestParams(), DefaultVerdictParams(), preds, stormy, nil))

	for _, out := range scenarios {
		assert.NotEmpty(t, out.Headline)
		for _, d := range out.Days {
			checkDay(t, d)
		}
	}
}

// setSaturdayPeaks replaces every Saturday peak height in preds.
func setSaturdayPeaks(preds []models.TidePrediction, ft float64) {
	for i := range preds {
		if preds[i].Time.In(eastern).Weekday() == time.Saturday {
			h := ft
			preds[i].Height = &h
		}
	}
}

func TestWeekendClosureRiskLabel(t *testing.T) {
	now, preds, land := quietWeek(t)
	build := func() WeekendOutlook {
		return BuildWeekendOutlook(now, testRamps(), weekendTestParams(), DefaultVerdictParams(), preds, land, nil)
	}

	// Quiet baseline: clear everywhere, and the label never names a ramp.
	nameRe := regexp.MustCompile(`3rd Ave|Crawford|Silver Beach`)
	for _, d := range build().Days {
		assert.Equal(t, "Clear all day", d.ClosureRiskLabel, d.Weekday)
	}

	// A possible-band peak at 1pm places the risk mid-day.
	setSaturdayPeaks(preds, 2.7)
	sat := day(t, build(), "Saturday")
	require.NotNil(t, sat)
	assert.Equal(t, "Mid-day close potential", sat.ClosureRiskLabel)
	assert.False(t, nameRe.MatchString(sat.ClosureRiskLabel), "the outlook must never name ramps")

	// A hard-close peak is an all-day story.
	setSaturdayPeaks(preds, 3.8)
	sat = day(t, build(), "Saturday")
	require.NotNil(t, sat)
	assert.Equal(t, "All-day close risk", sat.ClosureRiskLabel)
	assert.False(t, nameRe.MatchString(sat.ClosureRiskLabel))

	// Morning and late-day peaks together name both buckets.
	setSaturdayPeaks(preds, 2.0)
	for i := range preds {
		if preds[i].Time.In(eastern).Weekday() == time.Saturday {
			day := preds[i].Time.In(eastern)
			h1, h2 := 2.7, 2.7
			preds[i] = highAt(t, day.Format("2006-01-02")+" 09:00", h1)
			preds = append(preds, highAt(t, day.Format("2006-01-02")+" 17:30", h2))
			break
		}
	}
	sat = day(t, build(), "Saturday")
	require.NotNil(t, sat)
	assert.Equal(t, "Morning and late-day close potential", sat.ClosureRiskLabel)
}

func TestWeekendSurfLabel(t *testing.T) {
	now, preds, land := quietWeek(t)

	// No marine coverage: the label is absent.
	out := BuildWeekendOutlook(now, testRamps(), weekendTestParams(), DefaultVerdictParams(), preds, land, nil)
	for _, d := range out.Days {
		assert.Empty(t, d.SurfLabel, d.Weekday)
	}

	// Per-day blocks map through the surf-report height words.
	flat, knee := 1.0, 2.0
	blockFor := func(weekday string, ft *float64) nwsfc.WaveBlock {
		for _, d := range out.Days {
			if d.Weekday == weekday {
				return nwsfc.WaveBlock{Start: d.Schedule.OpensAt.UTC(), End: d.Schedule.ClosesAt.UTC(), HeightFt: ft}
			}
		}
		t.Fatalf("no %s in outlook", weekday)
		return nwsfc.WaveBlock{}
	}
	marine := &nwsfc.MarineForecast{Blocks: []nwsfc.WaveBlock{
		blockFor("Saturday", &flat),
		blockFor("Sunday", &knee),
	}}
	out = BuildWeekendOutlook(now, testRamps(), weekendTestParams(), DefaultVerdictParams(), preds, land, marine)

	sat, sun := day(t, out, "Saturday"), day(t, out, "Sunday")
	require.NotNil(t, sat)
	require.NotNil(t, sun)
	assert.Equal(t, "Flat", sat.SurfLabel)
	assert.Equal(t, "Knee-high", sun.SurfLabel)
	assert.Empty(t, day(t, out, "Monday").SurfLabel, "no block, no label")
}
