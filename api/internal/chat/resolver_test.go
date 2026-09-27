package chat

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/donwb/beach/api/internal/models"
)

func rosterFixture() []models.RampStatusWithSince {
	mk := func(id, name, city string) models.RampStatusWithSince {
		return models.RampStatusWithSince{RampStatus: models.RampStatus{AccessID: id, RampName: name, City: city}}
	}
	return []models.RampStatusWithSince{
		mk("NS-106", "BEACHWAY AV", "NEW SMYRNA BEACH"),
		mk("NS-108", "CRAWFORD RD", "NEW SMYRNA BEACH"),
		mk("NS-110", "FLAGLER AV", "NEW SMYRNA BEACH"),
		mk("NS-118", "3RD AV", "NEW SMYRNA BEACH"),
		mk("NS-141", "27TH AV", "NEW SMYRNA BEACH"),
		mk("DB-059", "INTERNATIONAL SPEEDWAY BLVD", "DAYTONA BEACH"),
		mk("DB-064", "SILVER BEACH AV", "DAYTONA BEACH"),
		mk("DBS-075", "VAN AV", "DAYTONA BEACH SHORES"),
		mk("DBS-076", "EL PORTAL ST", "DAYTONA BEACH SHORES"),
		mk("DBS-078", "DUNLAWTON BLVD", "DAYTONA BEACH SHORES"),
		mk("OB-034", "ROCKEFELLER DR", "ORMOND BEACH"),
		mk("OB-036", "CARDINAL DR", "ORMOND BEACH"),
		mk("OB-038", "HARVARD DR", "ORMOND BEACH"),
		mk("PI-097", "BEACH ST", "PONCE INLET"),
	}
}

func TestResolveExact(t *testing.T) {
	ramps := rosterFixture()
	tests := []struct {
		query string
		want  string
	}{
		{"flagler", "NS-110"},
		{"Flagler Ave", "NS-110"},
		{"the flagler avenue ramp", "NS-110"},
		{"Flagler in NSB", "NS-110"},
		{"27th", "NS-141"},
		{"27th Ave", "NS-141"},
		{"third avenue", "NS-118"},
		{"3rd", "NS-118"},
		{"cardinal", "OB-036"},
		{"Cardinal in Ormond", "OB-036"},
		{"dunlawton", "DBS-078"},
		{"Dunlawton Blvd approach", "DBS-078"},
		{"ISB", "DB-059"},
		{"international speedway", "DB-059"},
		{"silver beach", "DB-064"},
		{"el portal", "DBS-076"},
		{"beach street", "PI-097"},
		{"Beach St in Ponce", "PI-097"},
		{"rockefeller", "OB-034"},
		{"ns-110", "NS-110"},
		{"NS-110", "NS-110"},
	}
	for _, tt := range tests {
		t.Run(tt.query, func(t *testing.T) {
			res := Resolve(ramps, tt.query)
			require.NotEmpty(t, res.Matches, "no matches")
			assert.Equal(t, tt.want, res.Matches[0].AccessID)
			assert.True(t, res.Exact, "expected an exact match, got %+v", res.Matches)
		})
	}
}

func TestResolveAmbiguousAndMissing(t *testing.T) {
	ramps := rosterFixture()

	// A city alone lists its ramps, not exact.
	res := Resolve(ramps, "the Ormond ramps")
	assert.False(t, res.Exact)
	assert.Len(t, res.Matches, 3)

	// Nonsense hands back the roster grouped by city.
	res = Resolve(ramps, "zorblax")
	assert.False(t, res.Exact)
	assert.Empty(t, res.Matches)
	require.NotNil(t, res.AllRamps)
	assert.Len(t, res.AllRamps["New Smyrna Beach"], 5)

	// Display names come through the shared helper.
	res = Resolve(ramps, "flagler")
	assert.Equal(t, "Flagler Ave", res.Matches[0].Name)
	assert.Equal(t, "New Smyrna Beach", res.Matches[0].City)
}

func TestMeaningfulTokens(t *testing.T) {
	assert.Equal(t, []string{"flagler"}, meaningfulTokens("Flagler Ave"))
	assert.Equal(t, []string{"beach", "st"}, meaningfulTokens("BEACH ST"), "stop words stand when nothing else remains")
	assert.Equal(t, []string{"international", "speedway"}, meaningfulTokens("ISB"))
	assert.Equal(t, []string{"3rd"}, meaningfulTokens("third avenue"))
}
