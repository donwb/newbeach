package predict

import (
	"hash/fnv"
	"strings"
	"time"
)

// The voice layer: the quiet lines — the surf read and an all-open city
// verdict — rotate through small pools so a board watched every day does not
// say "Pretty much flat out there" five days running. Variation is
// deterministic: the pick is seeded by the Eastern date and the daypart, so
// every device shows the same phrase, nothing flips between 10-minute
// refreshes (the tvOS verdict bar flashes on headline change, and that flash
// must mean news), and the wording changes at most three times a day.
//
// Closure copy never rotates. "Closed", "possible around 2:30pm", reopen
// labels and the rip current relay are factual states with fenced wording.

// Daypart boundaries, Eastern: morning until 11, midday until 4, evening after.
const (
	daypartMorning = "morning"
	daypartMidday  = "midday"
	daypartEvening = "evening"
)

func daypartOf(now time.Time) string {
	switch h := now.In(eastern).Hour(); {
	case h < 11:
		return daypartMorning
	case h < 16:
		return daypartMidday
	default:
		return daypartEvening
	}
}

// voiceSeed is the stable key for one (day, daypart, salt) — the salt keeps
// the surf line and the verdict from always landing on the same index.
func voiceSeed(now time.Time, salt string) uint32 {
	et := now.In(eastern)
	h := fnv.New32a()
	h.Write([]byte(et.Format("2006-01-02")))
	h.Write([]byte("|" + daypartOf(now) + "|" + salt))
	return h.Sum32()
}

// pickVariant chooses one phrase from pool for this daypart. Empty pool → "".
func pickVariant(now time.Time, salt string, pool []string) string {
	if len(pool) == 0 {
		return ""
	}
	return pool[int(voiceSeed(now, salt)%uint32(len(pool)))]
}

// fillHeight substitutes the surfer-terms height label: {h} as written,
// {H} capitalized for sentence starts.
func fillHeight(s, heightLabel string) string {
	s = strings.ReplaceAll(s, "{h}", heightLabel)
	return strings.ReplaceAll(s, "{H}", capFirst(heightLabel))
}

// Surf pools. Local vocabulary on purpose — the Inlet (where the real surfers
// go), the break, the lineup, groms, Beachway (the ramp surfers take), NSB's
// sharks. Index 0 of each pool is the original line. Height-labelled pools
// use {h}/{H}; the unlabelled pools cover reads below knee-high.
var surfPools = map[string][]string{
	SurfFlat: {
		"Pretty much flat out there",
		"Lake Atlantic at the Inlet today",
		"Flat — only groms in the lineup",
		"Nothing breaking, not even at the Inlet",
		"Flat as glass — more sharks than sets",
		"Not a ripple at the break",
	},
	SurfBlown: {
		"Blown out — choppy and messy",
		"Blown out — the Inlet's a washing machine",
		"Victory at sea — onshore wrecked it",
		"Onshore mess · lineup's empty for a reason",
		"Blown to bits — nobody's at the break",
	},
	SurfChoppy: {
		"Rideable but choppy — {h} wind slop",
		"{H} wind slop — the groms will still go",
		"Bumpy {h} stuff at the break",
		"{H} and lumpy — the Inlet might hold it",
		"Choppy {h} · not worth the Beachway line",
	},
	SurfChoppy + ":nolabel": {
		"Rideable but choppy",
		"Small and wind-chopped",
		"Lumpy little bumps at the break",
		"Choppy scraps — groms only",
	},
	SurfCleanSmall: {
		"Fun {h} peelers out there",
		"Glassy {h} runners at the Inlet",
		"{H} and clean — grom heaven",
		"Small clean {h} at the break",
		"Mellow {h} peelers — easy lineup",
	},
	SurfCleanSmall + ":nolabel": {
		"Small and clean",
		"Tiny but glassy",
		"Ankle-slappers, but clean",
		"Glassy and small at the break",
	},
	SurfGood: {
		"Clean {h} — worth a paddle",
		"Clean {h} at the Inlet — lineup's filling in",
		"{H} and clean — take Beachway and go",
		"{H} lines at the break — worth the drive",
		"Proper {h} NSB surf — get in the lineup",
	},
	SurfFiring: {
		"About as good as it gets here — {h} and clean",
		"NSB is firing — {h} and clean",
		"{H} and clean at the Inlet — call in sick",
		"Firing — {h}, clean, and the lineup knows it",
		"{H} and pumping at the break — go now",
	},
}

// Quiet verdict headline pools for an all-open city with several ramps.
// {n} is the count word ("five"), {N} its capitalized form.
var allOpenHeadlines = []string{
	"All {n} open",
	"{N} for {n}",
	"Every ramp open",
	"Wide open — all {n}",
	"Nothing shut today",
	"All {n} ramps, all open",
}

// Quiet verdict detail lead-ins, followed by the driving-hours clause.
var noTideTroubleLeads = []string{
	"No tide trouble expected",
	"Tide's no threat today",
	"Nothing in the tide to worry about",
	"Easy tide day",
	"The tide's staying out of the way",
}

// allOpenHeadline is the rotating all-open headline for a city; single-ramp
// cities keep the fixed line.
func allOpenHeadline(now time.Time, rampCount int) string {
	if rampCount == 1 {
		return "The ramp is open"
	}
	n := countWord(rampCount)
	s := pickVariant(now, "verdict", allOpenHeadlines)
	s = strings.ReplaceAll(s, "{n}", n)
	return strings.ReplaceAll(s, "{N}", capFirst(n))
}
