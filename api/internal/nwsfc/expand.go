package nwsfc

import (
	"fmt"
	"regexp"
	"sort"
	"strconv"
	"time"
)

// gridpointResponse decodes the subset of GET /gridpoints/{office}/{x},{y}
// this package consumes. Every property is a valued series of validTime
// blocks; anything not listed here is ignored on decode.
type gridpointResponse struct {
	Properties struct {
		UpdateTime  string       `json:"updateTime"`
		Temperature valuedSeries `json:"temperature"`
		HeatIndex   valuedSeries `json:"heatIndex"`
		PoP         valuedSeries `json:"probabilityOfPrecipitation"`
		Thunder     valuedSeries `json:"probabilityOfThunder"`
		WindSpeed   valuedSeries `json:"windSpeed"`
		WindGust    valuedSeries `json:"windGust"`
		SkyCover    valuedSeries `json:"skyCover"`
		HeatRisk    valuedSeries `json:"heatRisk"`
		Hazards     hazardSeries `json:"hazards"`
		WaveHeight  valuedSeries `json:"waveHeight"`
		WavePeriod  valuedSeries `json:"wavePeriod"`
	} `json:"properties"`
}

type valuedSeries struct {
	UOM    string        `json:"uom"`
	Values []valuedPoint `json:"values"`
}

type valuedPoint struct {
	ValidTime string   `json:"validTime"`
	Value     *float64 `json:"value"`
}

type hazardSeries struct {
	Values []struct {
		ValidTime string `json:"validTime"`
		Value     []struct {
			Phenomenon   string `json:"phenomenon"`
			Significance string `json:"significance"`
		} `json:"value"`
	} `json:"values"`
}

// landHorizon caps how far the hourly expansion reaches. The NWS grid carries
// ~7 days; anything past that is noise for a weekend answer.
const landHorizon = 8 * 24 * time.Hour

// validTimeRe matches the ISO-8601 duration half of a gridpoint validTime,
// e.g. "PT1H", "PT13H", "P1D", "P1DT6H", "P2DT30M".
var validTimeRe = regexp.MustCompile(`^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?)?$`)

// expandValidTime parses a gridpoint validTime ("2026-08-18T18:00:00+00:00/PT3H")
// into its start instant and duration.
func expandValidTime(s string) (time.Time, time.Duration, error) {
	slash := -1
	for i, r := range s {
		if r == '/' {
			slash = i
			break
		}
	}
	if slash < 0 {
		return time.Time{}, 0, fmt.Errorf("validTime %q missing duration", s)
	}

	start, err := time.Parse(time.RFC3339, s[:slash])
	if err != nil {
		return time.Time{}, 0, fmt.Errorf("parsing validTime start %q: %w", s[:slash], err)
	}

	m := validTimeRe.FindStringSubmatch(s[slash+1:])
	if m == nil {
		return time.Time{}, 0, fmt.Errorf("unsupported validTime duration %q", s[slash+1:])
	}
	var dur time.Duration
	if m[1] != "" {
		d, _ := strconv.Atoi(m[1])
		dur += time.Duration(d) * 24 * time.Hour
	}
	if m[2] != "" {
		h, _ := strconv.Atoi(m[2])
		dur += time.Duration(h) * time.Hour
	}
	if m[3] != "" {
		mins, _ := strconv.Atoi(m[3])
		dur += time.Duration(mins) * time.Minute
	}
	if dur <= 0 {
		return time.Time{}, 0, fmt.Errorf("validTime %q has zero duration", s)
	}
	return start, dur, nil
}

// expandLand flattens a land gridpoint response into per-hour samples.
// Unparseable blocks are skipped, not fatal — the NWS occasionally emits odd
// validTimes and one bad block must not sink the forecast.
func expandLand(resp *gridpointResponse, fetchedAt time.Time) *LandForecast {
	byHour := map[time.Time]*HourlySample{}
	horizon := fetchedAt.Add(landHorizon)

	sample := func(t time.Time) *HourlySample {
		if s, ok := byHour[t]; ok {
			return s
		}
		s := &HourlySample{Time: t}
		byHour[t] = s
		return s
	}

	// apply walks a series' blocks hour by hour, converting each value and
	// assigning it via set.
	apply := func(series valuedSeries, convert func(float64) float64, set func(*HourlySample, float64)) {
		for _, v := range series.Values {
			if v.Value == nil {
				continue
			}
			start, dur, err := expandValidTime(v.ValidTime)
			if err != nil {
				continue
			}
			start = start.UTC().Truncate(time.Hour)
			for t := start; t.Before(start.Add(dur)) && t.Before(horizon); t = t.Add(time.Hour) {
				set(sample(t), convert(*v.Value))
			}
		}
	}

	identity := func(x float64) float64 { return x }

	p := resp.Properties
	apply(p.Temperature, celsiusToFahrenheit, func(s *HourlySample, v float64) { s.TempF = &v })
	apply(p.HeatIndex, celsiusToFahrenheit, func(s *HourlySample, v float64) { s.HeatIndexF = &v })
	apply(p.PoP, identity, func(s *HourlySample, v float64) { s.PoPPct = &v })
	apply(p.Thunder, identity, func(s *HourlySample, v float64) { s.ThunderPct = &v })
	apply(p.WindSpeed, kmhToMph, func(s *HourlySample, v float64) { s.WindMph = &v })
	apply(p.WindGust, kmhToMph, func(s *HourlySample, v float64) { s.GustMph = &v })
	apply(p.SkyCover, identity, func(s *HourlySample, v float64) { s.SkyCoverPct = &v })
	apply(p.HeatRisk, identity, func(s *HourlySample, v float64) { r := int(v); s.HeatRisk = &r })

	// Heat hazards: phenomenon HT (heat advisory/warning) or EH (excessive
	// heat) at any significance marks the covered hours.
	for _, hz := range p.Hazards.Values {
		heat := false
		for _, v := range hz.Value {
			if v.Phenomenon == "HT" || v.Phenomenon == "EH" {
				heat = true
			}
		}
		if !heat {
			continue
		}
		start, dur, err := expandValidTime(hz.ValidTime)
		if err != nil {
			continue
		}
		start = start.UTC().Truncate(time.Hour)
		for t := start; t.Before(start.Add(dur)) && t.Before(horizon); t = t.Add(time.Hour) {
			sample(t).HeatAdvisory = true
		}
	}

	hours := make([]HourlySample, 0, len(byHour))
	for _, s := range byHour {
		hours = append(hours, *s)
	}
	sort.Slice(hours, func(i, j int) bool { return hours[i].Time.Before(hours[j].Time) })

	return &LandForecast{FetchedAt: fetchedAt, Hours: hours}
}

// expandMarine converts a marine gridpoint response into wave blocks. Height
// blocks and period blocks are emitted independently (the two series rarely
// share boundaries).
func expandMarine(resp *gridpointResponse, fetchedAt time.Time) *MarineForecast {
	var blocks []WaveBlock

	// Wave height arrives in meters (uom wmoUnit:m).
	for _, v := range resp.Properties.WaveHeight.Values {
		if v.Value == nil {
			continue
		}
		start, dur, err := expandValidTime(v.ValidTime)
		if err != nil {
			continue
		}
		ft := metersToFeet(*v.Value)
		blocks = append(blocks, WaveBlock{Start: start.UTC(), End: start.UTC().Add(dur), HeightFt: &ft})
	}

	// Wave period is already in seconds.
	for _, v := range resp.Properties.WavePeriod.Values {
		if v.Value == nil {
			continue
		}
		start, dur, err := expandValidTime(v.ValidTime)
		if err != nil {
			continue
		}
		s := *v.Value
		blocks = append(blocks, WaveBlock{Start: start.UTC(), End: start.UTC().Add(dur), PeriodS: &s})
	}

	sort.Slice(blocks, func(i, j int) bool { return blocks[i].Start.Before(blocks[j].Start) })
	return &MarineForecast{FetchedAt: fetchedAt, Blocks: blocks}
}
