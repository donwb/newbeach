package chat

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/donwb/beach/api/internal/jev"
	"github.com/donwb/beach/api/internal/models"
)

// The routing eval: testdata/route_eval.json is a labeled set of first-turn
// questions in four groups — A shapes the pattern router knows, B questions
// that must reach the model, C paraphrases the patterns miss, D ramp
// questions (never quick before Jev). TestRegexRouteFixture pins the
// pattern router against it on every run. TestJevRouteEval runs the Jev
// router live (JEV_EVAL=1 + TYPESAFE_API_KEY) and prints the comparison
// that docs/JEV-SPIKE.md reports: coverage, wrong answers, latency, cost.
//
//	make jev-eval                   # in api/
//	JEV_EVAL_MODEL=1 make jev-eval  # also time the model path on the misses (ANTHROPIC_API_KEY)
//	JEV_EVAL_OUT=out.json           # write the rows

type evalPlan struct {
	Kind     string `json:"kind"`
	City     string `json:"city,omitempty"`
	AccessID string `json:"access_id,omitempty"`
	At       string `json:"at,omitempty"` // ET local, 2006-01-02T15:04:05
}

type evalCase struct {
	Group       string     `json:"group"`
	Q           string     `json:"q"`
	ContextCity string     `json:"context_city"`
	Want        []evalPlan `json:"want"` // empty = the model should read it
}

func (p evalPlan) plan(t *testing.T) quickPlan {
	out := quickPlan{Kind: p.Kind, City: p.City, AccessID: p.AccessID}
	if p.At != "" {
		at, err := time.ParseInLocation("2006-01-02T15:04:05", p.At, eastern)
		require.NoError(t, err)
		out.At = at
	}
	return out
}

func loadEval(t *testing.T) ([]evalCase, []models.RampStatusWithSince) {
	raw, err := os.ReadFile(filepath.Join("testdata", "route_eval.json"))
	require.NoError(t, err)
	var cases []evalCase
	require.NoError(t, json.Unmarshal(raw, &cases))

	raw, err = os.ReadFile(filepath.Join("testdata", "roster.json"))
	require.NoError(t, err)
	var rows []struct {
		AccessID string `json:"access_id"`
		RampName string `json:"ramp_name"`
		City     string `json:"city"`
	}
	require.NoError(t, json.Unmarshal(raw, &rows))
	ramps := make([]models.RampStatusWithSince, 0, len(rows))
	for _, r := range rows {
		var s models.RampStatusWithSince
		s.AccessID, s.RampName, s.City = r.AccessID, r.RampName, r.City
		ramps = append(ramps, s)
	}
	return cases, ramps
}

// grade: hit (a wanted plan), miss (wanted a plan, fell through), wrong
// (made a plan not wanted — the costly one), quiet (correctly fell
// through).
func grade(t *testing.T, c evalCase, plan quickPlan, ok bool) string {
	if !ok {
		if len(c.Want) == 0 {
			return "quiet"
		}
		return "miss"
	}
	for _, w := range c.Want {
		if w.plan(t).same(plan) {
			return "hit"
		}
	}
	return "wrong"
}

// The pattern router, pinned: every A case hits, everything else falls
// through. Moving a case between groups is a deliberate act.
func TestRegexRouteFixture(t *testing.T) {
	cases, _ := loadEval(t)
	now := fixedNow()
	for _, c := range cases {
		plan, ok := regexRoute(c.Q, c.ContextCity, now)
		g := grade(t, c, plan, ok)
		switch c.Group {
		case "A":
			assert.Equal(t, "hit", g, "%q → %s", c.Q, plan)
		case "B":
			assert.Equal(t, "quiet", g, "%q → %s", c.Q, plan)
		default:
			assert.Equal(t, "miss", g, "%q → %s (the pattern router is not supposed to know this one; move it to group A if it now does)", c.Q, plan)
		}
	}
}

type evalRow struct {
	Group      string   `json:"group"`
	Q          string   `json:"q"`
	Want       []string `json:"want"`
	Regex      string   `json:"regex_plan"`
	RegexGrade string   `json:"regex_grade"`
	Jev        string   `json:"jev_plan"`
	JevGrade   string   `json:"jev_grade"`
	JevReason  string   `json:"jev_reason,omitempty"`
	JevMs      int64    `json:"jev_ms"`
	JevTokens  int64    `json:"jev_tokens"`
	Intent     string   `json:"intent"`
	IntentConf float64  `json:"intent_conf"`
	ModelMs    int64    `json:"model_ms,omitempty"` // the model path, when timed
	ModelCalls int      `json:"model_calls,omitempty"`
}

func TestJevRouteEval(t *testing.T) {
	if os.Getenv("JEV_EVAL") == "" {
		t.Skip("set JEV_EVAL=1 (and TYPESAFE_API_KEY) to run the live routing eval")
	}
	key := os.Getenv("TYPESAFE_API_KEY")
	require.NotEmpty(t, key, "TYPESAFE_API_KEY")
	client := jev.New(key, jev.WithModel(os.Getenv("JEV_MODEL")), jev.WithTimeout(10*time.Second))

	cases, ramps := loadEval(t)
	now := fixedNow()
	ctx := context.Background()

	var modelRunner *Runner
	if os.Getenv("JEV_EVAL_MODEL") != "" && os.Getenv("ANTHROPIC_API_KEY") != "" {
		modelRunner = New(defaultFake(), os.Getenv("CHAT_MODEL"))
		if vm := os.Getenv("CHAT_VOICE_MODEL"); vm != "" {
			modelRunner.SetVoiceModel(vm)
		}
	}

	// Warm one call so the first measured latency is not a TLS handshake.
	_, _, _ = jevRoute(ctx, client, "is the beach open?", "nsb", now, ramps)

	var rows []evalRow
	var latencies []int64
	var tokens int64
	counts := map[string]map[string]int{routerRegex: {}, routerJev: {}}
	byGroup := map[string]map[string]map[string]int{}
	for _, c := range cases {
		rp, rok := regexRoute(c.Q, c.ContextCity, now)
		jp, tr, jok := jevRoute(ctx, client, c.Q, c.ContextCity, now, ramps)
		require.Empty(t, tr.Err, "jev call failed on %q", c.Q)
		row := evalRow{
			Group: c.Group, Q: c.Q,
			Regex: rp.String(), RegexGrade: grade(t, c, rp, rok),
			Jev: jp.String(), JevGrade: grade(t, c, jp, jok), JevReason: tr.Reason,
			JevMs: tr.Latency.Milliseconds(), JevTokens: tr.InputTokens,
			Intent: tr.Intent, IntentConf: round2(tr.IntentConf),
		}
		for _, w := range c.Want {
			row.Want = append(row.Want, w.plan(t).String())
		}
		if modelRunner != nil && !rok {
			start := time.Now()
			resp, err := modelRunner.Run(ctx, Request{Messages: []Turn{{Role: RoleUser, Text: c.Q}}, Context: &Context{City: c.ContextCity}, Voice: true})
			if err == nil {
				row.ModelMs = time.Since(start).Milliseconds()
				row.ModelCalls = resp.Usage.Calls
			} else {
				t.Logf("model path failed on %q: %v", c.Q, err)
			}
		}
		rows = append(rows, row)
		latencies = append(latencies, row.JevMs)
		tokens += row.JevTokens
		counts[routerRegex][row.RegexGrade]++
		counts[routerJev][row.JevGrade]++
		if byGroup[c.Group] == nil {
			byGroup[c.Group] = map[string]map[string]int{routerRegex: {}, routerJev: {}}
		}
		byGroup[c.Group][routerRegex][row.RegexGrade]++
		byGroup[c.Group][routerJev][row.JevGrade]++
	}

	// Report.
	var b strings.Builder
	fmt.Fprintf(&b, "\n## Routing eval — %d questions, model %s, clock %s\n\n", len(cases), client.Model(), now.Format("Mon 2006-01-02 3:04pm MST"))
	fmt.Fprintf(&b, "| router | hit | quiet | miss | wrong | answered quick |\n|---|---|---|---|---|---|\n")
	for _, r := range []string{routerRegex, routerJev} {
		c := counts[r]
		fmt.Fprintf(&b, "| %s | %d | %d | %d | %d | %d/%d |\n", r, c["hit"], c["quiet"], c["miss"], c["wrong"], c["hit"]+c["wrong"], len(cases))
	}
	fmt.Fprintf(&b, "\n| group | n | regex hit/quiet/miss/wrong | jev hit/quiet/miss/wrong |\n|---|---|---|---|\n")
	groups := make([]string, 0, len(byGroup))
	for g := range byGroup {
		groups = append(groups, g)
	}
	sort.Strings(groups)
	for _, g := range groups {
		r, j := byGroup[g][routerRegex], byGroup[g][routerJev]
		n := 0
		for _, v := range r {
			n += v
		}
		fmt.Fprintf(&b, "| %s | %d | %d/%d/%d/%d | %d/%d/%d/%d |\n", g, n,
			r["hit"], r["quiet"], r["miss"], r["wrong"], j["hit"], j["quiet"], j["miss"], j["wrong"])
	}
	sort.Slice(latencies, func(i, k int) bool { return latencies[i] < latencies[k] })
	pct := func(p float64) int64 { return latencies[int(float64(len(latencies)-1)*p)] }
	fmt.Fprintf(&b, "\nJev latency ms: p50 %d · p90 %d · p95 %d · max %d · mean tokens %d · cost/question $%.6f\n",
		pct(0.5), pct(0.9), pct(0.95), latencies[len(latencies)-1], tokens/int64(len(cases)), float64(tokens)/float64(len(cases))/1e6*0.042)

	if modelRunner != nil {
		var ms []int64
		var calls int
		for _, r := range rows {
			if r.ModelMs > 0 {
				ms = append(ms, r.ModelMs)
				calls += r.ModelCalls
			}
		}
		if len(ms) > 0 {
			sort.Slice(ms, func(i, k int) bool { return ms[i] < ms[k] })
			fmt.Fprintf(&b, "Model path (voice model, %d regex misses): p50 %d ms · min %d · max %d · mean calls %.1f\n",
				len(ms), ms[len(ms)/2], ms[0], ms[len(ms)-1], float64(calls)/float64(len(ms)))
		}
	}

	fmt.Fprintf(&b, "\n### Disagreements and errors\n\n| grp | question | want | regex | jev | conf | reason |\n|---|---|---|---|---|---|---|\n")
	for _, r := range rows {
		if r.RegexGrade == r.JevGrade && r.JevGrade != "wrong" && r.Regex == r.Jev {
			continue
		}
		fmt.Fprintf(&b, "| %s | %s | %s | %s (%s) | %s (%s) | %s %.2f | %s |\n", r.Group, r.Q, strings.Join(r.Want, " / "), r.Regex, r.RegexGrade, r.Jev, r.JevGrade, r.Intent, r.IntentConf, r.JevReason)
	}
	t.Log(b.String())
	fmt.Println(b.String())

	if out := os.Getenv("JEV_EVAL_OUT"); out != "" {
		raw, err := json.MarshalIndent(rows, "", " ")
		require.NoError(t, err)
		require.NoError(t, os.WriteFile(out, raw, 0o644))
	}
}
