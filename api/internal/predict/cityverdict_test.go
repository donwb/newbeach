package predict

import (
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/donwb/beach/api/internal/models"
)

// cityRamp builds a ramp with a city and optional status-since time.
func cityRamp(id int64, accessID, status, city string, since *time.Time) models.RampStatusWithSince {
	r := models.RampStatusWithSince{
		RampStatus: models.RampStatus{ID: id, AccessID: accessID, AccessStatus: status, City: city},
	}
	r.StatusSince = since
	return r
}

func verdictFor(t *testing.T, out Outlook, city string) CityVerdict {
	t.Helper()
	for _, cv := range out.Cities {
		if cv.City == city {
			return cv
		}
	}
	t.Fatalf("no verdict for %s in %+v", city, out.Cities)
	return CityVerdict{}
}

func TestCityVerdictAllOpenQuiet(t *testing.T) {
	now := et(1, 10, 0) // June: turtle season, 8am–7pm
	name := "3rd Ave"
	ramps := []models.RampStatusWithSince{
		cityRamp(1, "NS-141", "OPEN", "NEW SMYRNA BEACH", nil),
		cityRamp(2, "NS-106", "OPEN", "NEW SMYRNA BEACH", nil),
	}
	ramps[0].ShortName = &name
	preds := []models.TidePrediction{h(et(1, 13, 0), 1.8)} // below hard open

	out := BuildOutlook(now, ramps, Params{Default: DefaultParams}, preds, nil)
	require.Len(t, out.Cities, 1)

	cv := verdictFor(t, out, "NEW SMYRNA BEACH")
	assert.Equal(t, "New Smyrna Beach", cv.DisplayName)
	assert.Equal(t, CityStateAllOpen, cv.State)
	assert.Equal(t, "All two open", cv.Headline)
	assert.Equal(t, "No tide trouble expected · open for driving until 7pm", cv.Detail)
	assert.Equal(t, 2, cv.OpenCount)
	assert.Equal(t, 2, cv.RampCount)

	// The per-ramp outlooks carry the city key for client grouping.
	for _, ro := range out.Ramps {
		assert.Equal(t, "NEW SMYRNA BEACH", ro.City)
	}
}

func TestCityVerdictAtRisk(t *testing.T) {
	now := et(1, 10, 0)
	ramps := []models.RampStatusWithSince{
		cityRamp(1, "NS-141", "OPEN", "NEW SMYRNA BEACH", nil),
		cityRamp(2, "NS-106", "OPEN", "NEW SMYRNA BEACH", nil),
	}
	preds := []models.TidePrediction{h(et(1, 13, 0), 2.7)} // possible band

	out := BuildOutlook(now, ramps, Params{Default: DefaultParams}, preds, nil)
	cv := verdictFor(t, out, "NEW SMYRNA BEACH")

	assert.Equal(t, CityStateAllOpen, cv.State)
	assert.Equal(t, "All two open", cv.Headline)
	// Every ramp is at risk, so the copy says so. In the possible band each
	// ramp's own line quotes the peak itself, so the city line names the
	// peak once and does not tack on a "first around" that repeats it.
	assert.Equal(t, "Any of them could shut on the ~1pm high", cv.Detail)
}

func TestCityVerdictFirstAroundMatchesRampCopy(t *testing.T) {
	// Bug 2026-08-21: the city line said "first around 1:30pm" (the risk
	// window's start) while every ramp row said 2:30pm (peak minus lead).
	// The city must quote the earliest time a ramp line quotes — no other.
	now := et(1, 8, 30)
	ramps := []models.RampStatusWithSince{
		cityRamp(1, "NS-141", "OPEN", "NEW SMYRNA BEACH", nil),
		cityRamp(2, "NS-106", "OPEN", "NEW SMYRNA BEACH", nil),
	}
	preds := []models.TidePrediction{h(et(1, 13, 0), 3.4)} // likely band

	out := BuildOutlook(now, ramps, Params{Default: DefaultParams}, preds, nil)
	cv := verdictFor(t, out, "NEW SMYRNA BEACH")
	require.Equal(t, RiskLikely, out.Ramps[0].Risk)

	// The ramp's short copy is "tide closure possible ~H:MM" — lift the time.
	short := out.Ramps[0].Short
	idx := strings.LastIndex(short, "~")
	require.GreaterOrEqual(t, idx, 0, short)
	quoted := short[idx+1:]

	assert.Equal(t, "Any of them could shut on the ~1pm high · first around "+quoted, cv.Detail)
	// And it is not the window start, which sits earlier.
	require.NotNil(t, out.Ramps[0].Window)
	assert.NotEqual(t, fmtClock(out.Ramps[0].Window.Start), quoted)
}

func TestCityVerdictSomeClosed(t *testing.T) {
	now := et(1, 12, 0)
	since := et(1, 11, 40)
	name := "3rd Ave"
	ramps := []models.RampStatusWithSince{
		cityRamp(1, "NS-141", "CLOSED FOR HIGH TIDE", "NEW SMYRNA BEACH", &since),
		cityRamp(2, "NS-106", "OPEN", "NEW SMYRNA BEACH", nil),
	}
	ramps[0].ShortName = &name
	preds := []models.TidePrediction{h(et(1, 13, 0), 2.7)}

	out := BuildOutlook(now, ramps, Params{Default: DefaultParams}, preds, nil)
	cv := verdictFor(t, out, "NEW SMYRNA BEACH")

	assert.Equal(t, CityStateSomeClosed, cv.State)
	assert.Equal(t, "One of two open", cv.Headline)
	// The closed-since time is a fact and stays precise; the tide clause is a
	// prediction and stays hedged.
	assert.Equal(t, "3rd Ave closed for the tide since 11:40am · one more could shut on the ~1pm high", cv.Detail)
	assert.Equal(t, 1, cv.OpenCount)
}

func TestCityVerdictGolden(t *testing.T) {
	now := et(1, 18, 30) // 30 min before the 7pm turtle close
	ramps := []models.RampStatusWithSince{
		cityRamp(1, "NS-141", "OPEN", "NEW SMYRNA BEACH", nil),
		cityRamp(2, "NS-106", "OPEN", "NEW SMYRNA BEACH", nil),
	}
	preds := []models.TidePrediction{h(et(1, 13, 0), 1.8)}

	out := BuildOutlook(now, ramps, Params{Default: DefaultParams}, preds, nil)
	cv := verdictFor(t, out, "NEW SMYRNA BEACH")

	assert.Equal(t, CityStateGolden, cv.State)
	assert.Equal(t, "About half an hour of driving left", cv.Headline)
	assert.Equal(t, "All two open · gates close around 7pm", cv.Detail)

	// An hour-minus out, the bucket coarsens instead of counting minutes.
	out = BuildOutlook(et(1, 18, 5), ramps, Params{Default: DefaultParams}, preds, nil)
	cv = verdictFor(t, out, "NEW SMYRNA BEACH")
	assert.Equal(t, "Under an hour of driving left", cv.Headline)
}

func TestCityVerdictOvernight(t *testing.T) {
	ramps := []models.RampStatusWithSince{
		cityRamp(1, "NS-141", "OPEN", "NEW SMYRNA BEACH", nil),
	}
	preds := []models.TidePrediction{h(et(2, 13, 0), 1.8)}

	// Evening, after the close: the schedule has rolled to tomorrow.
	out := BuildOutlook(et(1, 21, 0), ramps, Params{Default: DefaultParams}, preds, nil)
	cv := verdictFor(t, out, "NEW SMYRNA BEACH")
	assert.Equal(t, CityStateOvernight, cv.State)
	assert.Equal(t, "Driving is done for the day", cv.Headline)
	assert.Equal(t, "Every ramp reopens around 8am, once ramps are cleared for turtles", cv.Detail)

	// Pre-dawn, before today's open: same state, morning voice.
	out = BuildOutlook(et(1, 5, 0), ramps, Params{Default: DefaultParams}, preds, nil)
	cv = verdictFor(t, out, "NEW SMYRNA BEACH")
	assert.Equal(t, CityStateOvernight, cv.State)
	assert.Equal(t, "Closed until morning", cv.Headline)
}

func TestCityVerdictGroupingAndOrder(t *testing.T) {
	now := et(1, 10, 0)
	ramps := []models.RampStatusWithSince{
		cityRamp(1, "NS-141", "OPEN", "NEW SMYRNA BEACH", nil),
		cityRamp(2, "DB-041", "OPEN", "DAYTONA BEACH", nil),
		cityRamp(3, "DB-042", "CLOSED - AT CAPACITY", "DAYTONA BEACH", nil),
		cityRamp(4, "XX-001", "OPEN", "", nil), // no city: contributes to no verdict
	}
	preds := []models.TidePrediction{h(et(1, 13, 0), 1.8)}

	out := BuildOutlook(now, ramps, Params{Default: DefaultParams}, preds, nil)
	require.Len(t, out.Cities, 2)
	assert.Equal(t, "DAYTONA BEACH", out.Cities[0].City, "alphabetical order")
	assert.Equal(t, "NEW SMYRNA BEACH", out.Cities[1].City)

	db := out.Cities[0]
	assert.Equal(t, CityStateSomeClosed, db.State)
	assert.Equal(t, "One of two open", db.Headline)
	// A non-tide closure gets the plain word, not the tide attribution.
	assert.Contains(t, db.Detail, "closed")
	assert.NotContains(t, db.Detail, "closed for the tide")
}

func TestCountWord(t *testing.T) {
	assert.Equal(t, "five", countWord(5))
	assert.Equal(t, "twelve", countWord(12))
	assert.Equal(t, "13", countWord(13))
}

func TestPrettyCityName(t *testing.T) {
	assert.Equal(t, "New Smyrna Beach", models.PrettyCityName("NEW SMYRNA BEACH"))
	assert.Equal(t, "Wilbur-by-the-Sea", models.PrettyCityName("WILBUR-BY-THE-SEA"))
	assert.Equal(t, "Ponce Inlet", models.PrettyCityName("PONCE INLET"))
}
