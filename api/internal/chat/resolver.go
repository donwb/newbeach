package chat

import (
	"sort"
	"strings"
	"unicode"

	"github.com/donwb/beach/api/internal/models"
	"github.com/donwb/beach/api/internal/predict"
)

// Candidate is one ramp a friendly name might mean.
type Candidate struct {
	AccessID string  `json:"access_id"`
	Name     string  `json:"name"`
	City     string  `json:"city"`
	Score    float64 `json:"-"`
}

// Resolution is what resolve_ramp hands back: the matches, whether the top
// one is unambiguous, and — when nothing matched — the whole roster grouped
// by city so the model can ask which one was meant.
type Resolution struct {
	Query    string                 `json:"query"`
	Exact    bool                   `json:"exact"`
	Matches  []Candidate            `json:"matches"`
	AllRamps map[string][]Candidate `json:"all_ramps,omitempty"`
	Note     string                 `json:"note,omitempty"`
}

// Two tiers of words never distinguish one ramp from another. grammarTokens
// are filler and are always dropped. roadTokens name the kind of road or the
// beach itself; they are dropped too — unless dropping them would leave
// nothing, because Beach St in Ponce Inlet is made of nothing else.
var grammarTokens = map[string]bool{
	"the": true, "a": true, "at": true, "on": true, "in": true, "of": true, "is": true,
	"ramp": true, "ramps": true, "approach": true, "access": true,
}

var roadTokens = map[string]bool{
	"av": true, "blvd": true, "st": true, "rd": true, "dr": true, "ln": true, "ct": true,
	"beach": true,
}

// tokenAliases rewrite a spoken form to the roster's spelling.
var tokenAliases = map[string]string{
	"ave": "av", "avenue": "av", "boulevard": "blvd", "street": "st", "road": "rd",
	"drive": "dr", "lane": "ln", "court": "ct",
	"third": "3rd", "3": "3rd",
	"twentyseventh": "27th", "27": "27th",
	"isb":          "international speedway",
	"speedway":     "international speedway",
	"portal":       "el portal",
	"rockerfeller": "rockefeller",
	"botefuhr":     "botefuhr", "botefur": "botefuhr",
}

// cityAliases map the words people use for a city to the GIS key. A query
// naming a city narrows the candidates to it.
var cityAliases = map[string]string{
	"nsb":                  "NEW SMYRNA BEACH",
	"smyrna":               "NEW SMYRNA BEACH",
	"new smyrna":           "NEW SMYRNA BEACH",
	"new smyrna beach":     "NEW SMYRNA BEACH",
	"daytona":              "DAYTONA BEACH",
	"daytona beach":        "DAYTONA BEACH",
	"shores":               "DAYTONA BEACH SHORES",
	"daytona shores":       "DAYTONA BEACH SHORES",
	"daytona beach shores": "DAYTONA BEACH SHORES",
	"ormond":               "ORMOND BEACH",
	"ormond beach":         "ORMOND BEACH",
	"ponce":                "PONCE INLET",
	"ponce inlet":          "PONCE INLET",
	"inlet":                "PONCE INLET",
}

// Cities in south-to-north order, GIS key → display name. The chat's
// "which cities?" answer and the fallback when a query names none.
var cityOrder = []string{"PONCE INLET", "NEW SMYRNA BEACH", "DAYTONA BEACH SHORES", "DAYTONA BEACH", "ORMOND BEACH"}

// ResolveCity maps the words people use for a city ("NSB", "Daytona", "the
// Shores", "New Smyrna Beach") to the GIS key. ok is false when nothing in
// the query names a city; "Daytona" alone means Daytona Beach, not the
// Shores — the alias table carries that call.
func ResolveCity(query string) (key, display string, ok bool) {
	q := strings.ToLower(strings.TrimSpace(query))
	if q == "" {
		return "", "", false
	}
	for _, k := range cityOrder {
		if strings.EqualFold(k, q) {
			return k, models.PrettyCityName(k), true
		}
	}
	key, _ = stripCity(q)
	if key == "" {
		return "", "", false
	}
	return key, models.PrettyCityName(key), true
}

// Resolve matches a friendly ramp name to the roster. An access id (any
// case) is exact; so is a query whose meaningful words are exactly a ramp's
// meaningful words and no other ramp's. Otherwise the best partial matches
// come back, worst-to-best trimmed to five, for the model to disambiguate.
func Resolve(ramps []models.RampStatusWithSince, query string) Resolution {
	res := Resolution{Query: query}
	q := strings.TrimSpace(query)
	if q == "" {
		res.AllRamps = roster(ramps)
		res.Note = "empty query; here is the roster"
		return res
	}

	// Access ids pass straight through.
	for i := range ramps {
		if strings.EqualFold(ramps[i].AccessID, q) {
			res.Exact = true
			res.Matches = []Candidate{candidate(ramps[i], 1)}
			return res
		}
	}

	lower := strings.ToLower(q)
	city, rest := stripCity(lower)
	qTokens := meaningfulTokens(rest)

	var scored []Candidate
	for i := range ramps {
		r := ramps[i]
		if city != "" && r.City != city {
			continue
		}
		nTokens := meaningfulTokens(strings.ToLower(r.RampName))
		if r.ShortName != nil && *r.ShortName != "" {
			nTokens = append(nTokens, meaningfulTokens(strings.ToLower(*r.ShortName))...)
		}
		s := overlap(qTokens, nTokens)
		if s >= 0.5 {
			scored = append(scored, candidate(r, s))
		}
	}

	// A city alone ("the Ormond ramps") lists that city.
	if len(qTokens) == 0 && city != "" {
		for i := range ramps {
			if ramps[i].City == city {
				scored = append(scored, candidate(ramps[i], 1))
			}
		}
		sort.Slice(scored, func(a, b int) bool { return scored[a].Name < scored[b].Name })
		res.Matches = scored
		res.Note = "the query named a city, not a ramp; these are its ramps"
		return res
	}

	sort.SliceStable(scored, func(a, b int) bool { return scored[a].Score > scored[b].Score })
	if len(scored) > 5 {
		scored = scored[:5]
	}
	res.Matches = scored
	if len(scored) == 0 {
		res.AllRamps = roster(ramps)
		res.Note = "no ramp matched; ask which of these was meant"
		return res
	}
	if scored[0].Score >= 0.999 && (len(scored) == 1 || scored[1].Score < 0.999) {
		res.Exact = true
	}
	return res
}

func candidate(r models.RampStatusWithSince, score float64) Candidate {
	return Candidate{
		AccessID: r.AccessID,
		Name:     predict.RampDisplayName(r),
		City:     models.PrettyCityName(r.City),
		Score:    score,
	}
}

// roster groups every ramp by pretty city name, sorted for a stable payload.
func roster(ramps []models.RampStatusWithSince) map[string][]Candidate {
	out := map[string][]Candidate{}
	for i := range ramps {
		c := candidate(ramps[i], 0)
		out[c.City] = append(out[c.City], c)
	}
	for k := range out {
		sort.Slice(out[k], func(a, b int) bool { return out[k][a].Name < out[k][b].Name })
	}
	return out
}

// stripCity finds a city alias in the query (longest first) and returns the
// GIS city key plus the query with the alias removed.
func stripCity(q string) (city, rest string) {
	best := ""
	for alias := range cityAliases {
		if len(alias) > len(best) && containsPhrase(q, alias) {
			best = alias
		}
	}
	if best == "" {
		return "", q
	}
	return cityAliases[best], strings.Replace(q, best, " ", 1)
}

// containsPhrase reports whether phrase appears in s on word boundaries.
func containsPhrase(s, phrase string) bool {
	idx := strings.Index(s, phrase)
	for idx >= 0 {
		before := idx == 0 || !isWordChar(rune(s[idx-1]))
		end := idx + len(phrase)
		after := end == len(s) || !isWordChar(rune(s[end]))
		if before && after {
			return true
		}
		next := strings.Index(s[idx+1:], phrase)
		if next < 0 {
			return false
		}
		idx += 1 + next
	}
	return false
}

func isWordChar(r rune) bool { return unicode.IsLetter(r) || unicode.IsDigit(r) }

// meaningfulTokens lowercases, splits on anything that is not a letter or
// digit, applies the aliases, and drops the two tiers of stop words: filler
// always, road words unless nothing else remains.
func meaningfulTokens(s string) []string {
	raw := strings.FieldsFunc(strings.ToLower(s), func(r rune) bool { return !isWordChar(r) })
	var content []string
	for _, t := range raw {
		if a, ok := tokenAliases[t]; ok {
			for _, f := range strings.Fields(a) {
				if !grammarTokens[f] {
					content = append(content, f)
				}
			}
			continue
		}
		if !grammarTokens[t] {
			content = append(content, t)
		}
	}
	content = dedupe(content)
	var kept []string
	for _, t := range content {
		if !roadTokens[t] {
			kept = append(kept, t)
		}
	}
	if len(kept) == 0 {
		return content
	}
	return kept
}

// dedupe keeps the first occurrence of each token, so an alias that expands
// to words already present ("speedway" inside "International Speedway")
// does not count twice.
func dedupe(tokens []string) []string {
	seen := make(map[string]bool, len(tokens))
	out := tokens[:0]
	for _, t := range tokens {
		if !seen[t] {
			seen[t] = true
			out = append(out, t)
		}
	}
	return out
}

// overlap scores how well the query's words cover a name's words: matched
// words over the larger of the two sets, so "flagler" against "flagler" is
// 1 and "flagler" against "silver" is 0. A query word also matches a name
// word it is a prefix of when it is at least four letters, so "rocke"
// finds Rockefeller.
func overlap(q, name []string) float64 {
	if len(q) == 0 || len(name) == 0 {
		return 0
	}
	matched := 0
	used := make([]bool, len(name))
	for _, qt := range q {
		for i, nt := range name {
			if used[i] {
				continue
			}
			if qt == nt || (len(qt) >= 4 && strings.HasPrefix(nt, qt)) {
				used[i] = true
				matched++
				break
			}
		}
	}
	denom := len(q)
	if len(name) > denom {
		denom = len(name)
	}
	return float64(matched) / float64(denom)
}
