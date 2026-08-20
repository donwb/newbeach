package predict

import (
	"sort"
	"time"

	"github.com/donwb/beach/api/internal/models"
)

// City verdict states — the resting screen's accent-bar vocabulary. A third
// fenced enum: not the risk grades (which score one ramp against one tide)
// and not the weekend verdicts (which grade a future day). Nothing else may
// borrow these.
const (
	CityStateAllOpen    = "all_open"
	CityStateSomeClosed = "some_closed"
	CityStateGolden     = "golden"
	CityStateOvernight  = "overnight"
)

// goldenWindow: within this long of the day's close, an all-open city's
// verdict switches to the wrap-up story.
const goldenWindow = time.Hour

// CityVerdict is one city's across-the-room answer: a headline, its detail
// line, and the state that colors the accent bar. Headline and detail are
// rendered verbatim by clients.
type CityVerdict struct {
	City        string `json:"city"`         // raw GIS key, matches ramp .city
	DisplayName string `json:"display_name"` // "New Smyrna Beach"
	State       string `json:"state"`
	Headline    string `json:"headline"`
	Detail      string `json:"detail"`
	OpenCount   int    `json:"open_count"`
	RampCount   int    `json:"ramp_count"`
}

// notOpenRamp carries what the copy needs about a ramp that is not plain open.
type notOpenRamp struct {
	name     string
	status   string // raw access status
	category string // "limited" or "closed"
	since    *time.Time
}

// cityAgg collects one city's facts during the verdict pass.
type cityAgg struct {
	rampCount      int
	openCount      int
	notOpen        []notOpenRamp
	atRisk         int        // open ramps the tide could still close today
	earliestWindow *time.Time // start of the earliest at-risk window
}

// buildCityVerdicts groups the built outlook by city and writes each city's
// verdict. ramps and outlooks are parallel — BuildOutlook appends exactly one
// outlook per ramp, in order.
func buildCityVerdicts(now time.Time, ramps []models.RampStatusWithSince, outlooks []RampOutlook, sched Schedule, season string, tide TideContext) []CityVerdict {
	aggs := map[string]*cityAgg{}
	for i := range ramps {
		city := ramps[i].City
		if city == "" || i >= len(outlooks) {
			continue
		}
		agg := aggs[city]
		if agg == nil {
			agg = &cityAgg{}
			aggs[city] = agg
		}
		agg.rampCount++

		cat := models.StatusToCategory(ramps[i].AccessStatus)
		if cat == "open" {
			agg.openCount++
		} else {
			agg.notOpen = append(agg.notOpen, notOpenRamp{
				name:     rampDisplayName(ramps[i]),
				status:   ramps[i].AccessStatus,
				category: cat,
				since:    ramps[i].StatusSince,
			})
		}

		ro := &outlooks[i]
		if cat == "open" && ro.Reason == ReasonHighTide && riskRank(ro.Risk) >= 1 {
			agg.atRisk++
			if ro.Window != nil {
				if agg.earliestWindow == nil || ro.Window.Start.Before(*agg.earliestWindow) {
					t := ro.Window.Start
					agg.earliestWindow = &t
				}
			}
		}
	}

	overnight := sched.OpensAt != nil && now.Before(*sched.OpensAt)
	golden := sched.ClosesAt != nil && !now.Before(sched.ClosesAt.Add(-goldenWindow)) && now.Before(*sched.ClosesAt)

	keys := make([]string, 0, len(aggs))
	for k := range aggs {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	verdicts := make([]CityVerdict, 0, len(keys))
	for _, k := range keys {
		agg := aggs[k]
		cv := CityVerdict{
			City:        k,
			DisplayName: models.PrettyCityName(k),
			OpenCount:   agg.openCount,
			RampCount:   agg.rampCount,
		}
		switch {
		case overnight:
			cv.State = CityStateOvernight
			cv.Headline, cv.Detail = cityOvernightText(now, season, sched)
		case len(agg.notOpen) > 0:
			cv.State = CityStateSomeClosed
			cv.Headline, cv.Detail = citySomeClosedText(agg, sched, tide)
		case golden:
			cv.State = CityStateGolden
			cv.Headline, cv.Detail = cityGoldenText(now, agg, season, sched)
		default:
			cv.State = CityStateAllOpen
			cv.Headline, cv.Detail = cityAllOpenText(now, agg, sched, tide)
		}
		verdicts = append(verdicts, cv)
	}
	return verdicts
}

// rampDisplayName prefers the curated short name, then the pretty GIS name,
// then the access id.
func rampDisplayName(r models.RampStatusWithSince) string {
	if r.ShortName != nil && *r.ShortName != "" {
		return *r.ShortName
	}
	if n := models.PrettyRampName(r.RampName); n != "" {
		return n
	}
	return r.AccessID
}
