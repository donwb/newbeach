# Jev spike — a System One model in the Ask path

**Started 2026-09-29.** Jev is TypeSafe's "System One" model
([docs](https://docs.typesafe.ai/llms.txt)): it takes a *state* and a map of
typed questions and returns typed answers with calibrated probabilities — a
Choice from a fixed set, a Noul (probability a statement is true), a Score
along ordered levels. It never generates text. Input-only pricing
($0.042/Mtok), ~100 ms per call, 64k context, text only.

The spike asks two questions, using this repo as the test bed:

1. **Is Ask faster with Jev routing than with the pattern router?**
2. **Is the code less brittle or simpler — does Jev replace the regexes?**

## Verdict (Don, 2026-09-29): not worth switching on here

The improvement is real but marginal: seconds saved, for one user, a
handful of times a week, against a third-party dependency with rate limits
still in flux, another secret, and a probabilistic component in a path that
was deterministic. **The code stays** — isolated, off without a key, and the
labeled fixture plus the pinned regex test are useful regardless — but
`TYPESAFE_API_KEY` is not set in prod and `JEV_MODE` should stay off.

Why the case was weak, and the lesson for the toolbox:

- **Right shape, wrong economics.** Routing a question into a bounded set
  is exactly what Jev is for. But Jev earns its dependency only when one of
  these holds: volume makes model calls cost real money; latency is on a hard
  budget with no acceptable slow path; calibrated probabilities are needed to
  act unattended; there is no good fallback. Here the fallback (the model) is
  fine, just slower, and Siri's budget is the only one of the four that even
  partly applies.
- **Built around not having it.** The quick path was designed regex-first
  with a model fallback, and Jev was bolted in as a third tier. Designed from
  scratch with Jev available there would be no regex tier: Jev routes
  everything, the model handles only open-ended questions, the resolver's
  alias table becomes option descriptions. The spike proved that design works
  (no wrong plan on either set) — it just would not have changed the
  economics.
- **Where to reach for it next:** a high-volume classifier or verifier,
  anything you would otherwise fine-tune a small model for, or a guard behind
  generation at scale where a regex genuinely cannot keep up.
- **What transfers regardless of Jev:** one judgment per question, no
  distractors in the state, gate on the probability of the outcome class
  code acts on rather than a peakedness statistic, and spell boundaries into
  the criteria. Those are the rules for any calibrated-decision model.

## What was built

Four uses, all inside `api/internal/chat`, all behind one switch:

| # | Where | Before | With Jev |
|---|---|---|---|
| 1 | Quick-path router (`route.go`, `jevroute.go`) | Five regexes recognise three question shapes (city now, city at a time, best day); anything else costs a model round-trip | One System One call: Choice questions for intent, city, ramp, day, daypart, hour, minute, meridiem. Code assembles the instant with the same calendar rules as before |
| 2 | Ramp resolution | The resolver scores candidates and the model disambiguates, so ramp questions were never quick | The roster is a 28-option Choice in the same call; "is Flagler open?" and "Beachway Saturday at 2pm" answer from engine copy |
| 3 | Copy guard (`guard.go`) | Three regexes: a promise pattern, the reserved word "likely", a minute-precise clock | The promise rule is a Noul over `{reply, engine_lines}`. The other two stay in code on purpose (a reserved word is a literal check; a clock time is a number) |
| 4 | Scope / past detection | The system prompt tells the model to decline | `intent: past | other` in the same call sends those straight to the model with no quick attempt |

`api/internal/jev` is the client: one POST, typed question builders, a
2 s timeout, one retry on 429/529. TypeSafe ships Python and JS SDKs only;
the HTTP contract is small enough that the wrapper is the SDK.

### Modes (`JEV_MODE`)

- `off` — the pattern router and pattern guard, Jev never called. Also the
  effective mode without `TYPESAFE_API_KEY`.
- `shadow` (default) — the pattern router answers; Jev runs beside it, off
  the request's clock, and every disagreement is logged (`chat.route.shadow`,
  `chat.guard.shadow`). This is how evidence accumulates from real questions.
- `on` — Jev answers. The pattern router covers only a Jev outage; a
  low-confidence answer goes to the model, not to the regex.

Gates (`jevroute.go`): intent probability ≥ 0.7, every other consumed
Choice ≥ 0.6 on the probability of its *outcome class* (options code treats
identically are summed), the roster pick ≥ 0.5 with a ≥ 0.25 margin over the
runner-up; guard promise Noul > 0.6 (`guard.go`). Start conservative, tune
against logs.

### Design rules followed (from Jev's own jaggedness page)

- **Numbers and calendars stay in code.** Jev names the day and the clock
  components as closed sets; `whenFromParts` does the arithmetic, the
  "1–7 means afternoon" rule, the same-weekday ambiguity, the past check.
- **Literal questions.** Every criterion says exactly what counts. The board
  city is *not* in the state — Jev is asked "which city does the question
  name", and code applies the context fallback, so the model can't be
  tempted to answer from the hint.
- **Filter the state.** State is `{question, today_weekday}` — nothing else.
- **Select, don't generate.** The ramp question is a Choice over the roster;
  Jev never has to spell a ramp name.
- **Provider behind an interface.** A nil client is `off`; every Jev failure
  degrades to the previous behaviour, never to no behaviour.

## Measurement

The eval: `api/internal/chat/testdata/route_eval.json`, 64 labeled first-turn
questions in four groups, graded hit / quiet / miss / wrong against an
acceptable-plan list:

- **A (19)** — shapes the pattern router knows. Pinned by
  `TestRegexRouteFixture` on every `go test`: all 19 hit, and every other
  group misses (moving a question between groups is a deliberate act).
- **B (16)** — must reach the model: the past, vague futures, off-topic,
  follow-ups, no city anywhere.
- **C (15)** — paraphrases of A the patterns miss ("any chance of getting
  on the sand in New Smyrna at the moment?", "open?" with a board city).
- **D (14)** — ramp questions, never quick before.

Run it: `make jev-eval` in `api/` (needs `TYPESAFE_API_KEY`).
`JEV_EVAL_FIXTURE=route_holdout.json` runs the held-out set;
`JEV_EVAL_MODEL=1` also times the real model path on the pattern router's
misses (needs `ANTHROPIC_API_KEY`; a few cents). `TestJevGuardEval` (same
gate) runs the guard Noul over ten replies.

### Results (2026-09-29, `jev-1.13.0` via `jev-latest`, run from the Studio)

**Tuning set** (`route_eval.json`, 64 questions). The questions were rewritten
three times against this set, so treat it as training data — it shows what
the router *can* do once the questions are literal enough, not what it does
unseen.

| router | hit | quiet | miss | wrong | answered quick |
|---|---|---|---|---|---|
| pattern | 19 | 17 | 28 | 0 | 19/64 |
| Jev, first draft | 27 | 15 | 16 | 6* | 33/64 |
| Jev, after rewriting the questions | 49 | 15 | 0 | 0 | 49/64 |

\* five of the six were a grader bug (the expected ramp plan lacked the
city the router fills in); the real wrong answer was "what about tomorrow?"
with a board city, which on a first turn is a defensible read and was
relabeled as either-is-fine.

**Held-out set** (`route_holdout.json`, 25 fresh phrasings written after
tuning, run once, not tuned on):

| router | hit | quiet | miss | wrong | answered quick |
|---|---|---|---|---|---|
| pattern | 1 | 6 | 17 | 1 | 2/25 |
| Jev | 15 | 6 | 3 | 1 | 16/25 |

The one "wrong" on each side was the same case and was my label, not the
routers: both answered "are the ramps open at 6:45 tonight" as 6:45pm, which
the engine can replay; the fixture now says so. The three Jev misses all fell
through to the model, never to a wrong plan: "Ormond, tomorrow around 11?"
(intent 0.55, too terse), "what's the beach looking like this evening"
(read as conditions, arguably right), "Should we go this weekend at all?"
(read as other, 0.51). **No harmful wrong answer on either set.**

**Latency and cost** (Studio → api.typesafe.ai, roster in every call):

| | p50 | p90 | p95 | max | tokens | cost |
|---|---|---|---|---|---|---|
| Jev router | 178 ms | 216 | 244 | 289 | ~2,670 in | $0.00011 / question |

Roughly half the tokens are the 28-ramp roster. Output tokens are free.

**Guard** (10 replies against one possible-risk source, judged by a careful
editor): the promise regex agreed with the editor on 6/10, the Jev Noul on
10/10. The regex misses "count on it being shut", "expect it to be closed",
"is going to be a problem" and trips on "will not close". The Noul's values
were well separated: 0.13–0.20 on clean replies, 0.88–0.96 on promises, and
0.50 on the one genuinely mixed reply ("the beach will be open… Flagler could
shut"), which the 0.6 floor lets through. The shadow-only `unsupported_claim`
Noul is noisier (0.59 on a verbatim reply) and stays a log line.

### What the misses taught (the three rewrites)

Every miss in the first draft traced to a question I wrote ambiguously,
exactly as Jev's jaggedness page predicts. The fixes, in order of effect:

1. **One judgment per question.** The first intent Choice asked "city
   status or ramp status?" and split on "Are the New Smyrna ramps open?"
   (0.41). Now intent is only *what kind of question*; whether a ramp is
   named is the roster Choice's job, and code combines them.
2. **Don't put a distractor in the state.** `today_weekday: Wednesday` made
   "Ormond ramps — open or closed?" pick day=wednesday (0.51). The state is
   now the question alone; code knows the calendar.
3. **Gate on outcome-class probability, not the confidence statistic.**
   "unstated" and "today" both mean now, and "now" and "afternoon" both mean
   2pm on a future day; confidence measures peakedness and punished exactly
   those overlaps. The gates sum the probabilities of options code treats
   the same. The roster Choice (28 options) is gated on the pick's own
   probability and its margin, since peakedness runs low there by
   construction.
4. **Spell the boundary into the criteria.** "noon" is midday, not a clock
   time; "usually/normally/ever" is other, not status; "Saturday or Sunday
   — which is better?" is best_day; "at Granada" names a ramp; the
   resolver's aliases (ISB, Third, Portal) ride in the option descriptions.

### Answering question 1: is Ask faster?

Two different questions hide in there.

- **Per quick answer, Jev is slower than the regex.** ~180 ms against
  effectively zero. On a Siri intent that is inaudible.
- **Per question, Ask gets faster in proportion to what the regex missed.**
  Every miss is a model round-trip (2–3 Sonnet/Opus calls with a tool loop:
  seconds). On the tuning set the quick path grows from 19 to 49 of 64; on
  the held-out set from 2 to 16 of 25. Every one of those is a multi-second
  answer that became a ~200 ms one.

The model path was not timed in this run: `ANTHROPIC_API_KEY` is not in the
local `.env` and the prod logs no longer hold `chat.done` lines. The eval
supports it (`JEV_EVAL_MODEL=1 make jev-eval`, a few cents) and the doc
should carry that number once it has been run.

## Answering question 2 now: simplicity and brittleness

Line counts, honestly:

| | pattern router | Jev router |
|---|---|---|
| recognisers | 5 regexes + `quickWhen` (89 lines) + `weekdayFor` (19) + `regexRoute` (27) | `routeQuestions` (82 lines of question text) + `assemblePlan` (70) + `whenFromParts` (83) |
| question shapes covered | 3 (city now, city at, best day) | 5 (+ ramp now, ramp at), plus every paraphrase of them |
| guard | 3 regexes, 48 lines | 1 Noul (46 lines) + the 2 literal regexes kept |

**Jev did not make the code shorter.** The calendar arithmetic is the same
size either way because it was always code's job. What changed is *what
kind* of code it is:

- The recognisers went from procedural patterns (`\b(can (i|we) (get|drive|go)
  (on|onto|out on) the beach|…`) to declarative descriptions ("Whether the
  beach, the ramps, or beach driving — in a named city or in general — is
  open…"). Adding a phrasing is adding an example to a sentence, not
  extending a regex and re-checking every alternation.
- Coverage went from "shapes we enumerated" to "shapes the engine can
  answer". The C and D groups exist because the regexes could not grow into
  them; the Jev router covers them with no new code paths.
- Brittleness moved rather than vanished. The regex fails *silently and
  predictably* (a miss costs a model call). The Jev router fails
  *probabilistically*: the wrong column in the eval is the number that
  matters, because a confident wrong plan answers the wrong question in the
  engine's voice. The confidence floors and the model fallback are the
  containment.
- Two of the three guard regexes stayed. That is the design rule, not a
  failure: a reserved word and a clock format are literal checks and code is
  the right judge. Jev replaced the one regex that was doing a judgment's job.

## Where it does not belong

The prediction engine. It is already a calibrated decision system —
thresholds learned from real closures on numeric inputs — which is the one
category Jev's docs say it is bad at. Jev is the language layer around the
engine, never inside it.
