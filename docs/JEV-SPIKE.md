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

Confidence floors: intent ≥ 0.7, every other consumed Choice ≥ 0.6
(`jevroute.go`); guard promise Noul > 0.6 (`guard.go`). Start
conservative, tune against logs.

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
`JEV_EVAL_MODEL=1` also times the real model path on the pattern router's
misses (needs `ANTHROPIC_API_KEY`; a few cents).

### Results

_Pending the first live run — this section is filled in from `make jev-eval`
output._

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
