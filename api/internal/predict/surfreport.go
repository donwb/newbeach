package predict

import (
	"sort"
	"strings"
	"time"

	"github.com/donwb/beach/api/internal/models"
	"github.com/donwb/beach/api/internal/weather"
)

// The surf report is one casual line about the break, rendered verbatim by
// clients — an adjective, not a feature. It is deliberately separate from
// SurfContext (the model echo of what conditioned the risk calls) and from
// the fenced risk enum: nothing here feeds or reads closure grading. The rip
// current risk is relayed verbatim from the NWS Surf Zone Forecast, never
// computed.

// Surf quality buckets, worst to best. Like the verdicts, these exist so a
// client can branch on an icon or color without parsing prose.
const (
	SurfFlat       = "flat"
	SurfBlown      = "blown"
	SurfChoppy     = "choppy"
	SurfCleanSmall = "clean_small"
	SurfGood       = "good"
	SurfFiring     = "firing"
)

// coastNormalDeg is the direction the beach faces: the New Smyrna / Ponce
// Inlet strand runs roughly north–south and faces east. Wind FROM within 45°
// of this bearing is onshore; from the opposite quadrant, offshore.
const coastNormalDeg = 90.0

// SurfReport is the beach-wide casual surf line served on the outlook.
type SurfReport struct {
	Line        string     `json:"line"`
	Quality     string     `json:"quality,omitempty"`
	HeightLabel string     `json:"height_label,omitempty"`
	RipRisk     string     `json:"rip_risk,omitempty"` // NWS SRF verbatim: Low|Moderate|High
	ObservedAt  *time.Time `json:"observed_at,omitempty"`
}

// surfHeightLabel maps buoy significant wave height to surfer terms.
func surfHeightLabel(ft float64) string {
	switch {
	case ft < 1.5:
		return ""
	case ft < 2.5:
		return "knee-high"
	case ft < 3.5:
		return "waist-high"
	case ft < 4.5:
		return "chest-high"
	case ft < 6.5:
		return "head-high"
	default:
		return "overhead"
	}
}

// surfDayLabel renders a forecast day's max wave height as one card word,
// reusing the report's height vocabulary so the app speaks one surf language.
func surfDayLabel(ft *float64) string {
	if ft == nil {
		return ""
	}
	label := surfHeightLabel(*ft)
	if label == "" {
		return "Flat"
	}
	return strings.ToUpper(label[:1]) + label[1:]
}

// windShore classifies a wind direction (degrees FROM) against the coast:
// "onshore", "offshore", or "cross".
func windShore(dirDeg float64) string {
	diff := dirDeg - coastNormalDeg
	for diff < -180 {
		diff += 360
	}
	for diff > 180 {
		diff -= 360
	}
	switch {
	case diff >= -45 && diff <= 45:
		return "onshore"
	case diff <= -135 || diff >= 135:
		return "offshore"
	default:
		return "cross"
	}
}

// surfQuality is the deterministic classifier: buckets checked worst-first,
// one answer per input. Missing wind skips the wind-dependent branches;
// missing period is treated as neutral.
func surfQuality(heightFt float64, periodS, windDirDeg, windMph *float64) string {
	windKnown := windDirDeg != nil && windMph != nil
	shore := ""
	if windKnown {
		shore = windShore(*windDirDeg)
	}

	switch {
	case heightFt < 1.5:
		return SurfFlat
	case windKnown && shore == "onshore" && *windMph >= 15:
		return SurfBlown
	case (windKnown && shore == "onshore" && *windMph >= 8) ||
		(periodS != nil && *periodS < 7):
		return SurfChoppy
	case heightFt >= 4.5 && periodS != nil && *periodS >= 10 &&
		(!windKnown || shore == "offshore" || *windMph < 8):
		return SurfFiring
	case heightFt >= 3.5 && periodS != nil && *periodS >= 8 &&
		(!windKnown || shore == "offshore" || *windMph < 15):
		return SurfGood
	default:
		return SurfCleanSmall
	}
}

// surfPhrase is the base line for a bucket — one of the pool's phrases for
// this daypart, with the height label filled in. See voice.go.
func surfPhrase(now time.Time, quality, heightLabel string) string {
	key := quality
	if heightLabel == "" && (quality == SurfChoppy || quality == SurfCleanSmall) {
		key += ":nolabel"
	}
	return fillHeight(pickVariant(now, "surf", surfPools[key]), heightLabel)
}

// surfPlaces is the local shorthand for each GIS city key, in coast order
// south to north — the way a surfer would list them. The rank sorts a
// multi-city clause so it reads up the coast, never alphabetically.
var surfPlaces = map[string]struct {
	name string
	rank int
}{
	"NEW SMYRNA BEACH":     {"NSB", 0},
	"PONCE INLET":          {"Ponce", 1},
	"WILBUR-BY-THE-SEA":    {"Wilbur", 2},
	"DAYTONA BEACH SHORES": {"the Shores", 3},
	"DAYTONA BEACH":        {"Daytona", 4},
	"ORMOND BEACH":         {"Ormond", 5},
	"ORMOND-BY-THE-SEA":    {"Ormond-by-the-Sea", 6},
}

// surfPlaceList renders a set of GIS city keys as "Daytona and the Shores"
// / "NSB, Daytona and Ormond", coast order, unknown keys prettified last.
func surfPlaceList(cities map[string]bool) string {
	type place struct {
		name string
		rank int
	}
	var places []place
	for key := range cities {
		if sp, ok := surfPlaces[key]; ok {
			places = append(places, place{sp.name, sp.rank})
		} else {
			places = append(places, place{models.PrettyCityName(key), 100})
		}
	}
	sort.Slice(places, func(i, j int) bool {
		if places[i].rank != places[j].rank {
			return places[i].rank < places[j].rank
		}
		return places[i].name < places[j].name
	})
	names := make([]string, len(places))
	for i, p := range places {
		names[i] = p.name
	}
	switch len(names) {
	case 0:
		return ""
	case 1:
		return names[0]
	default:
		return strings.Join(names[:len(names)-1], ", ") + " and " + names[len(names)-1]
	}
}

// tideClause appends the ramp-access angle — the sentence only this app can
// write — reusing the already-built ramp outlooks. No tide math happens here.
//
// The surf line is beach-wide (one buoy) but it renders on per-city boards,
// so the clause says WHERE: "ramps are tide-closed right now" is only true
// when every city has a ramp shut; otherwise it names the cities, so a
// New Smyrna board reading "Every ramp open" can sit above "...tide-closed
// right now in Daytona and the Shores" without contradicting itself.
func tideClause(out *Outlook) string {
	worst := ""
	var closeAt *time.Time // earliest time a likely ramp's own copy quotes
	allCities := map[string]bool{}
	byTier := map[string]map[string]bool{ // tier -> cities with a ramp in it
		RiskClosedNow: {}, RiskLikely: {}, RiskPossible: {},
	}
	for i := range out.Ramps {
		ro := &out.Ramps[i]
		allCities[ro.City] = true
		if ro.Reason != ReasonHighTide {
			continue
		}
		switch ro.Risk {
		case RiskClosedNow:
			worst = RiskClosedNow
		case RiskLikely:
			if worst != RiskClosedNow {
				worst = RiskLikely
			}
			if ro.quotedClose != nil && (closeAt == nil || ro.quotedClose.Before(*closeAt)) {
				closeAt = ro.quotedClose
			}
		case RiskPossible:
			if worst == "" {
				worst = RiskPossible
			}
		default:
			continue
		}
		byTier[ro.Risk][ro.City] = true
	}
	if worst == "" {
		return ""
	}
	// "where" is empty when the tier's cities cover the whole county — the
	// bare county-wide line is then the honest one.
	where := ""
	if len(byTier[worst]) < len(allCities) {
		where = " in " + surfPlaceList(byTier[worst])
	}
	switch {
	case worst == RiskClosedNow:
		return ", but ramps are tide-closed right now" + where
	case worst == RiskLikely && closeAt != nil:
		return ", but a closure's possible around " + fmtClock(*closeAt) + where
	case where != "":
		return ", though the high tide could shut ramps" + where + " for a bit"
	default:
		return ", though the high tide could shut ramps for a bit"
	}
}

// BuildSurfReport composes the surf line. Pure; every input degrades: a nil
// or stale (> maxWaveAge) wave drops the height read, nil conditions drop
// wind phrasing, nil srf drops the rip risk. The rip risk rides in the
// RipRisk field for the clients' facts row, never in the prose — except when
// there is no wave read at all, where an elevated official call is the only
// thing worth a line. Returns nil when there is nothing worth saying.
func BuildSurfReport(now time.Time, out *Outlook, wave *models.WaveSample, cond *weather.Conditions, srf *weather.SurfZone) *SurfReport {
	// A stale buoy read is no read.
	if wave != nil {
		age := now.Sub(wave.Time)
		if age < 0 {
			age = -age
		}
		if age > maxWaveAge {
			wave = nil
		}
	}

	rip := ""
	if srf != nil {
		rip = srf.RipCurrentRisk
	}
	ripElevated := rip == "Moderate" || rip == "High"

	if wave == nil {
		// No surf read. An elevated official rip call is still worth
		// relaying on its own; otherwise there is no report.
		if !ripElevated {
			return nil
		}
		return &SurfReport{
			Line:    "Heads up — rip current risk is " + strings.ToLower(rip) + " today",
			RipRisk: rip,
		}
	}

	var windDirDeg, windMph *float64
	if cond != nil {
		windDirDeg, windMph = cond.WindDirDeg, cond.WindSpeedMph
	}

	quality := surfQuality(wave.HeightFt, wave.DominantPeriodS, windDirDeg, windMph)
	heightLabel := surfHeightLabel(wave.HeightFt)
	line := surfPhrase(now, quality, heightLabel)

	// The access angle rides along only when the surf is worth driving to —
	// "blown out, but a closure's possible" is noise.
	if quality == SurfCleanSmall || quality == SurfGood || quality == SurfFiring {
		line += tideClause(out)
	}
	obs := wave.Time
	return &SurfReport{
		Line:        line,
		Quality:     quality,
		HeightLabel: heightLabel,
		RipRisk:     rip,
		ObservedAt:  &obs,
	}
}
