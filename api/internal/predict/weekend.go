package predict

import (
	"slices"
	"sort"
	"time"

	"github.com/donwb/beach/api/internal/models"
	"github.com/donwb/beach/api/internal/nwsfc"
)

// Weekend verdicts grade a FUTURE day as a whole. They are a separate
// vocabulary from the risk enum on purpose: none/possible/likely grade one
// thing (the chance the tide closes a ramp today) and are read that way by
// the backtest and scorecard — the weekend feature must never borrow them.
const (
	VerdictGreat  = "great"
	VerdictGood   = "good"
	VerdictMixed  = "mixed"
	VerdictTough  = "tough"
	VerdictNoCall = "no_call"
)

// Closure pressure summarizes the county-wide tide picture for a day —
// factual aggregation over per-ramp riskForPeak calls, not a new risk grade.
const (
	PressureNone = "none"
	PressureSome = "some"
	PressureHigh = "high"
)

// Verdict drivers name the check that actually set a day's grade, so the
// copy (and clients) can always answer "why this pill?". A driver is binding
// — it enforced the rank the day landed on — not merely a condition that
// fired and was shadowed by something worse.
const (
	DriverTide   = "tide"
	DriverStorms = "storms"
	DriverWind   = "wind"
	DriverHeat   = "heat"
	DriverCold   = "cold"
)

// WeekendParamsKey is the settings-table key holding the tunable verdict
// thresholds. The numbers are experiential (what actually keeps Don home),
// so they are editable live via /api/v2/admin/settings rather than compiled
// in — when a rendered verdict disagrees with a real weekend, turn the knob.
const WeekendParamsKey = "weekend_verdict_params"

// VerdictParams are the weather thresholds behind the day verdicts. Defaults
// come from the 2026-08-18 calibration interview.
type VerdictParams struct {
	// Storm hours: an hour blocks the best window when thunder or rain
	// probability crosses these. Probability alone never sinks a day —
	// Florida afternoons live at 50% — timing does.
	ThunderBlockPct float64 `json:"thunder_block_pct"`
	RainBlockPct    float64 `json:"rain_block_pct"`
	// StormWashoutFrac: only when storm-blocked hours cover this fraction of
	// the driving day does the verdict itself take the hit.
	StormWashoutFrac float64 `json:"storm_washout_frac"`

	// Wind: sustained at WindDegradeMph starts degrading the day; gusts at
	// GustToughMph are stay-home territory.
	WindDegradeMph float64 `json:"wind_degrade_mph"`
	GustToughMph   float64 `json:"gust_tough_mph"`

	// Heat: an NWS heat hazard or a heat index at HeatIndexF downgrades and
	// biases the best window toward morning.
	HeatIndexF float64 `json:"heat_index_f"`

	// Cold: a day high below ColdHighF is a walk, not a beach day.
	ColdHighF float64 `json:"cold_high_f"`
}

// DefaultVerdictParams returns the interview-calibrated defaults.
func DefaultVerdictParams() VerdictParams {
	return VerdictParams{
		ThunderBlockPct:  40,
		RainBlockPct:     60,
		StormWashoutFrac: 0.75,
		WindDegradeMph:   15,
		GustToughMph:     25,
		HeatIndexF:       105,
		ColdHighF:        65,
	}
}

// weekendHorizonDays is how many days the weekend outlook covers. Day seven
// usually sits past the NWS gridpoint horizon and degrades to the honest
// tide-only path ("No weather call for this day yet").
const weekendHorizonDays = 7

// WeekendDay is one future day's answer. Headline/Detail are rendered
// verbatim; the typed fields exist so clients can branch (pill color,
// attribute chips) without parsing prose.
type WeekendDay struct {
	Date            string   `json:"date"` // Eastern calendar date, "2026-08-22"
	Weekday         string   `json:"weekday"`
	IsWeekend       bool     `json:"is_weekend"`
	Verdict         string   `json:"verdict"`
	Drivers         []string `json:"drivers,omitempty"` // what set the verdict, e.g. "heat"
	Basis           []string `json:"basis"`             // "tide" (+"weather") (+"marine")
	Headline        string   `json:"headline"`
	Why             string   `json:"why,omitempty"` // pill justification, only when the headline doesn't carry it
	Detail          string   `json:"detail,omitempty"`
	BestWindow      *Window  `json:"best_window,omitempty"`
	ClosurePressure string   `json:"closure_pressure"`
	Schedule        Schedule `json:"schedule"`

	// ClosureRiskLabel is the day's closure story in one casual phrase
	// ("Mid-day close potential", "Clear all day"). Deliberately vague about
	// which ramps: this far out the tide is knowable and the individual gates
	// are not, so it warns about the beach day and never names a ramp.
	// SurfLabel is the day's forecast surf in the surf report's height words
	// ("Flat", "Knee-high"); absent without marine coverage.
	ClosureRiskLabel string `json:"closure_risk_label"`
	SurfLabel        string `json:"surf_label,omitempty"`

	// Supporting attributes for the day cards — they back the verdict, they
	// are not a forecast page. FeelsLikeF is the day's max heat index, sent
	// only when it meaningfully exceeds the air temp: 90° undersells a 108°
	// heat index, and the heat index is what the verdict actually reads.
	HighTempF     *float64 `json:"high_temp_f,omitempty"`
	FeelsLikeF    *float64 `json:"feels_like_f,omitempty"`
	RainChancePct *float64 `json:"rain_chance_pct,omitempty"`
	WindLabel     string   `json:"wind_label,omitempty"`
}

// WeekendOutlook is the response served at /api/v2/outlook/weekend.
type WeekendOutlook struct {
	GeneratedAt time.Time    `json:"generated_at"`
	Headline    string       `json:"headline"`
	Days        []WeekendDay `json:"days"`
}

// dayFacts is everything dayVerdict and dayText need about one day, gathered
// in one pass so the pieces stay consistent with each other.
type dayFacts struct {
	daysOut  int
	frame    Schedule
	pressure string
	dicey    []string // short names of the first-to-close ramps, worst first

	hasWeather bool // land forecast covers this day's driving hours
	hasMarine  bool

	maxTempF      *float64
	maxHeatIdxF   *float64
	heatAdvisory  bool
	maxWindMph    *float64
	maxGustMph    *float64
	maxPoPPct     *float64
	stormFrac     float64    // fraction of driving hours storm-blocked
	firstStormAt  *time.Time // start of the first storm-blocked hour
	tidePeaks     []models.TidePrediction
	blockedRanges []timeRange
	tideWindows   []timeRange // tide closure windows only, for the risk label
	anyHardClose  bool        // a peak at/above the hard-close cutoff
	marineMaxFt   *float64    // day's max forecast wave height
}

type timeRange struct{ start, end time.Time }

// BuildWeekendOutlook computes the multi-day outlook. Pure — no I/O. preds
// must cover [now, now + weekendHorizonDays]; land/marine are nil-tolerant
// (a day without forecast coverage gets an honest tide-only verdict, and its
// basis says so).
// prior is each ramp's previous-day fact (priorDayFacts), nil for none; the
// planner carries it forward height-anchored (persistDayShift).
func BuildWeekendOutlook(now time.Time, ramps []models.RampStatusWithSince, params Params, vp VerdictParams, preds []models.TidePrediction, land *nwsfc.LandForecast, marine *nwsfc.MarineForecast, prior map[string]PriorDay) WeekendOutlook {
	out := WeekendOutlook{GeneratedAt: now.UTC()}

	// Today stays in the list only while its driving day is live.
	startOffset := 0
	if _, closes, ok := postedHours(now); ok && !now.Before(closes.Add(params.dayCloseOffset())) {
		startOffset = 1
	}

	for i := startOffset; i < startOffset+weekendHorizonDays; i++ {
		dayAnchor := now.In(eastern).AddDate(0, 0, i)
		opens, closes, ok := postedHours(dayAnchor)
		if !ok {
			continue
		}
		closes = closes.Add(params.dayCloseOffset())

		frame := Schedule{OpensAt: &opens, ClosesAt: &closes}
		frame.OpensLabel = "around " + fmtClock(roundNearest30(opens))
		frame.ClosesLabel = "around " + fmtClock(roundNearest30(closes))

		facts := gatherDayFacts(now, i, frame, ramps, params, vp, preds, land, marine, prior)
		day := WeekendDay{
			Date:            dayAnchor.Format("2006-01-02"),
			Weekday:         dayAnchor.Weekday().String(),
			IsWeekend:       dayAnchor.Weekday() == time.Saturday || dayAnchor.Weekday() == time.Sunday,
			ClosurePressure: facts.pressure,
			Schedule:        frame,
			Basis:           facts.basis(),
			HighTempF:       facts.maxTempF,
			RainChancePct:   facts.maxPoPPct,
			WindLabel:       windLabel(facts.maxWindMph, facts.maxGustMph),
		}
		if facts.maxHeatIdxF != nil && facts.maxTempF != nil && *facts.maxHeatIdxF >= *facts.maxTempF+5 {
			day.FeelsLikeF = facts.maxHeatIdxF
		}
		day.Verdict, day.Drivers = dayVerdict(facts, vp)
		day.BestWindow = bestWindow(now, i, frame, facts, vp)
		day.Headline, day.Detail = dayText(day.Verdict, facts, day.BestWindow, vp)
		day.Why = whyText(day.Verdict, day.Drivers, facts, vp, day.Headline)
		day.ClosureRiskLabel = closureRiskLabel(facts)
		day.SurfLabel = surfDayLabel(facts.marineMaxFt)
		out.Days = append(out.Days, day)
	}

	out.Headline = weekendHeadline(out.Days)
	return out
}

// basis lists what informed the day, so degradation is explicit.
func (f *dayFacts) basis() []string {
	b := []string{"tide"}
	if f.hasWeather {
		b = append(b, "weather")
	}
	if f.hasMarine {
		b = append(b, "marine")
	}
	return b
}

// forecastDayShift maps a forecast wave height to the county-wide threshold
// shift for a future day. It reuses the learned regime boundaries — NWS
// marine waveHeight is the same significant-wave-height quantity the regimes
// were trained on — but with a guard the live path doesn't need: the calm
// raise (which relaxes closure calls) only applies near-term and comfortably
// inside the calm regime, because a forecast must never promise openness it
// can't back. The rough drop (which hedges toward "possible") always applies.
func forecastDayShift(params Params, heightFt, periodS *float64, daysOut int) float64 {
	if heightFt == nil || params.Waves == nil {
		return 0
	}
	shift := params.waveShiftFor(heightFt, periodS)
	if shift > 0 && (daysOut > 3 || *heightFt > params.Waves.CalmMaxFt-0.3) {
		return 0
	}
	return shift
}

// gatherDayFacts assembles one day's tide pressure and weather aggregates.
func gatherDayFacts(now time.Time, daysOut int, frame Schedule, ramps []models.RampStatusWithSince, params Params, vp VerdictParams, preds []models.TidePrediction, land *nwsfc.LandForecast, marine *nwsfc.MarineForecast, prior map[string]PriorDay) dayFacts {
	facts := dayFacts{daysOut: daysOut, frame: frame, pressure: PressureNone}
	opens, closes := *frame.OpensAt, *frame.ClosesAt

	// Effective start: for today, the day is already partly spent.
	from := opens
	if daysOut == 0 && now.After(from) {
		from = now
	}

	// Daytime tide peaks for this frame (an hour of slack past close, same
	// as the live outlook's filter).
	for _, p := range preds {
		if p.Type != "H" || p.Height == nil {
			continue
		}
		if p.Time.Before(from.Add(-peakLookback)) || p.Time.After(closes.Add(time.Hour)) {
			continue
		}
		facts.tidePeaks = append(facts.tidePeaks, p)
	}

	// Marine shift for the day.
	var dayShift float64
	if marine != nil {
		if h := marine.MaxHeightFtBetween(opens.UTC(), closes.UTC()); h != nil {
			facts.hasMarine = true
			facts.marineMaxFt = h
			dayShift = forecastDayShift(params, h, marine.MaxPeriodSBetween(opens.UTC(), closes.UTC()), daysOut)
		}
	}

	// County-wide closure pressure: run every peak against every ramp.
	type diceyRamp struct {
		name        string
		thresholdFt float64
	}
	var dicey []diceyRamp
	likelyCount, rampCount := 0, 0
	anyPossible := false
	for _, p := range facts.tidePeaks {
		if *p.Height >= params.hardClose() {
			facts.anyHardClose = true
		}
	}
	for _, ramp := range ramps {
		rp, _ := effectiveParams(ramp.AccessID, ramp.ClosureHeightFt, params)
		rampCount++
		worst := RiskNone
		pd := prior[ramp.AccessID]
		for _, p := range facts.tidePeaks {
			shift := clampTotalShift(dayShift + params.persistDayShift(pd, rp, *p.Height, daysOut))
			r := riskForPeak(*p.Height, shift, rp, params.hardOpen(), params.hardClose())
			if riskRank(r) > riskRank(worst) {
				worst = r
			}
		}
		if riskRank(worst) >= 1 {
			anyPossible = true
			name := models.PrettyRampName(ramp.RampName)
			if ramp.ShortName != nil && *ramp.ShortName != "" {
				name = *ramp.ShortName
			}
			if name == "" {
				name = ramp.AccessID
			}
			dicey = append(dicey, diceyRamp{name: name, thresholdFt: rp.ThresholdFt})
		}
		if worst == RiskLikely {
			likelyCount++
		}
	}
	switch {
	case facts.anyHardClose || (rampCount > 0 && likelyCount*2 > rampCount):
		facts.pressure = PressureHigh
	case anyPossible:
		facts.pressure = PressureSome
	}
	// First-to-close ramps (lowest threshold) lead the copy; cap at three.
	sort.Slice(dicey, func(i, j int) bool { return dicey[i].thresholdFt < dicey[j].thresholdFt })
	for i := 0; i < len(dicey) && i < 3; i++ {
		facts.dicey = append(facts.dicey, dicey[i].name)
	}

	// Tide closure windows block best-window slots (county default lead/lag).
	// Kept separately in tideWindows too, so the closure-risk label can place
	// them in the day without confusing them with storm blocks.
	if facts.pressure != PressureNone {
		for _, p := range facts.tidePeaks {
			if riskForPeak(*p.Height, dayShift, params.Default, params.hardOpen(), params.hardClose()) == RiskNone {
				continue
			}
			if w := closureWindow(p, params.Default, frame); w != nil {
				facts.blockedRanges = append(facts.blockedRanges, timeRange{w.Start, w.End})
				facts.tideWindows = append(facts.tideWindows, timeRange{w.Start, w.End})
			}
		}
	}

	// Weather aggregates over driving hours.
	if land != nil {
		drivingHours, coveredHours, stormHours := 0, 0, 0
		for _, h := range land.Hours {
			if h.Time.Before(from.UTC()) || !h.Time.Before(closes.UTC()) {
				continue
			}
			drivingHours++
			if h.TempF != nil || h.PoPPct != nil || h.WindMph != nil {
				coveredHours++
			}
			maxFloat(&facts.maxTempF, h.TempF)
			maxFloat(&facts.maxHeatIdxF, h.HeatIndexF)
			maxFloat(&facts.maxWindMph, h.WindMph)
			maxFloat(&facts.maxGustMph, h.GustMph)
			maxFloat(&facts.maxPoPPct, h.PoPPct)
			if h.HeatAdvisory {
				facts.heatAdvisory = true
			}

			stormy := (h.ThunderPct != nil && *h.ThunderPct >= vp.ThunderBlockPct) ||
				(h.PoPPct != nil && *h.PoPPct >= vp.RainBlockPct)
			if stormy {
				stormHours++
				facts.blockedRanges = append(facts.blockedRanges, timeRange{h.Time, h.Time.Add(time.Hour)})
				if facts.firstStormAt == nil {
					t := h.Time
					facts.firstStormAt = &t
				}
			}
		}
		// "Has weather" means real coverage, not one straggler hour at the
		// edge of the grid.
		if drivingHours > 0 && coveredHours*2 >= drivingHours {
			facts.hasWeather = true
			facts.stormFrac = float64(stormHours) / float64(drivingHours)
		}
	}

	return facts
}

// maxFloat folds src into dst, keeping the max.
func maxFloat(dst **float64, src *float64) {
	if src == nil {
		return
	}
	if *dst == nil || *src > **dst {
		v := *src
		*dst = &v
	}
}

// dayVerdict collapses a day's facts into one verdict. Caps push down, never
// up, so multiple problems can't cancel out. The second return names the
// binding drivers — the checks whose enforced rank is the rank the day
// landed on — so the copy can always say why the pill reads what it reads.
func dayVerdict(facts dayFacts, vp VerdictParams) (string, []string) {
	// Without weather coverage the answer is honest but modest: tides alone
	// can't promise a great day.
	v := VerdictGreat
	if !facts.hasWeather {
		v = VerdictGood
	}

	type hit struct {
		driver string
		rank   int
	}
	var hits []hit

	cap := func(driver, limit string) {
		hits = append(hits, hit{driver, verdictRank(limit)})
		if verdictRank(limit) < verdictRank(v) {
			v = limit
		}
	}
	downgrade := func(driver string) {
		if verdictRank(v) > verdictRank(VerdictTough) {
			v = verdictAtRank(verdictRank(v) - 1)
			hits = append(hits, hit{driver, verdictRank(v)})
		}
	}

	// Tide pressure.
	switch facts.pressure {
	case PressureHigh:
		cap(DriverTide, VerdictMixed)
	case PressureSome:
		cap(DriverTide, VerdictGood)
	}

	if facts.hasWeather {
		// Storms cap the day only when they wash most of it out — otherwise
		// they just shape the window (the calibration rule: timing, not
		// probability). A real storm block still keeps the day from reading
		// "great": part of it is spoken for.
		switch {
		case facts.stormFrac >= vp.StormWashoutFrac:
			cap(DriverStorms, VerdictMixed)
		case facts.stormFrac >= 0.15:
			cap(DriverStorms, VerdictGood)
		}

		// Wind.
		if facts.maxGustMph != nil && *facts.maxGustMph >= vp.GustToughMph {
			cap(DriverWind, VerdictTough)
		} else if facts.maxWindMph != nil && *facts.maxWindMph >= vp.WindDegradeMph {
			downgrade(DriverWind)
		}

		// Heat.
		if facts.heatAdvisory || (facts.maxHeatIdxF != nil && *facts.maxHeatIdxF >= vp.HeatIndexF) {
			downgrade(DriverHeat)
		}

		// Cold.
		if facts.maxTempF != nil && *facts.maxTempF < vp.ColdHighF {
			downgrade(DriverCold)
		}
	}

	if v == VerdictGreat {
		return v, nil
	}
	var drivers []string
	for _, h := range hits {
		if h.rank == verdictRank(v) && !slices.Contains(drivers, h.driver) {
			drivers = append(drivers, h.driver)
		}
	}
	return v, drivers
}

func verdictRank(v string) int {
	switch v {
	case VerdictGreat:
		return 3
	case VerdictGood:
		return 2
	case VerdictMixed:
		return 1
	default: // tough, no_call
		return 0
	}
}

func verdictAtRank(r int) string {
	switch r {
	case 3:
		return VerdictGreat
	case 2:
		return VerdictGood
	case 1:
		return VerdictMixed
	default:
		return VerdictTough
	}
}

// bestWindow finds the longest unblocked run of half-hour slots inside the
// day's driving frame. On extreme-heat days ties (and near-ties) break
// toward the morning end.
func bestWindow(now time.Time, daysOut int, frame Schedule, facts dayFacts, vp VerdictParams) *Window {
	from, to := *frame.OpensAt, *frame.ClosesAt
	if daysOut == 0 && now.After(from) {
		from = now
	}
	from = roundUp30(from)
	to = roundDown30(to)
	if !to.After(from) {
		return nil
	}

	blocked := func(slotStart time.Time) bool {
		slotEnd := slotStart.Add(30 * time.Minute)
		for _, r := range facts.blockedRanges {
			if slotStart.Before(r.end) && r.start.Before(slotEnd) {
				return true
			}
		}
		return false
	}

	type run struct {
		start time.Time
		dur   time.Duration
	}
	var runs []run
	var cur *run
	for t := from; t.Before(to); t = t.Add(30 * time.Minute) {
		if blocked(t) {
			cur = nil
			continue
		}
		if cur == nil {
			runs = append(runs, run{start: t})
			cur = &runs[len(runs)-1]
		}
		cur.dur += 30 * time.Minute
	}
	if len(runs) == 0 {
		return nil
	}

	best := runs[0]
	for _, r := range runs[1:] {
		if r.dur > best.dur {
			best = r
		}
	}

	// Extreme heat: prefer the earliest run that's still most of the best —
	// a 9am–1pm stretch beats a marginally longer late-afternoon bake.
	extremeHeat := facts.heatAdvisory || (facts.maxHeatIdxF != nil && *facts.maxHeatIdxF >= vp.HeatIndexF)
	if extremeHeat {
		for _, r := range runs {
			if float64(r.dur) >= 0.75*float64(best.dur) {
				best = r
				break
			}
		}
	}

	if best.dur < 2*time.Hour {
		return nil
	}

	// A window spanning the whole (remaining) day carries no extra
	// information — the copy says "any time works" instead.
	if best.start.Equal(from) && best.dur >= to.Sub(from) {
		return nil
	}

	start := roundDown30(best.start)
	end := roundUp30(best.start.Add(best.dur))
	if end.After(to) {
		end = to
	}
	return &Window{Label: clockRange(start, end), Start: start, End: end}
}

// windLabel renders the day's wind as one casual chip label.
func windLabel(windMph, gustMph *float64) string {
	switch {
	case gustMph != nil && *gustMph >= 25:
		return "gusty"
	case windMph != nil && *windMph >= 15:
		return "windy"
	case windMph != nil && *windMph >= 8:
		return "breezy"
	case windMph != nil:
		return "light wind"
	default:
		return ""
	}
}
