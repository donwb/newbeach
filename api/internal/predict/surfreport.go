package predict

import (
	"fmt"
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

// tideClause appends the ramp-access angle — the sentence only this app can
// write — reusing the already-built ramp outlooks. No tide math happens here.
func tideClause(out *Outlook) string {
	worst := ""
	var closeAt *time.Time // earliest time a likely ramp's own copy quotes
	for i := range out.Ramps {
		ro := &out.Ramps[i]
		if ro.Reason != ReasonHighTide {
			continue
		}
		switch ro.Risk {
		case RiskClosedNow:
			return ", but ramps are tide-closed right now"
		case RiskLikely:
			worst = RiskLikely
			if ro.quotedClose != nil && (closeAt == nil || ro.quotedClose.Before(*closeAt)) {
				closeAt = ro.quotedClose
			}
		case RiskPossible:
			if worst == "" {
				worst = RiskPossible
			}
		}
	}
	switch {
	case worst == RiskLikely && closeAt != nil:
		return ", but a closure's possible around " + fmtClock(*closeAt)
	case worst != "":
		return ", though the high tide could shut ramps for a bit"
	default:
		return ""
	}
}

// BuildSurfReport composes the surf line. Pure; every input degrades: a nil
// or stale (> maxWaveAge) wave drops the height read, nil conditions drop
// wind phrasing, nil srf drops the rip risk. Returns nil when there is
// nothing worth saying.
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
	if ripElevated {
		line += fmt.Sprintf(" · rip current risk is %s today", strings.ToLower(rip))
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
