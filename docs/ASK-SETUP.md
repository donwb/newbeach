# Ask (chat) — keys and switch-on

The Ask feature (`POST /api/v2/chat`, the chat sheet on iOS, the "Ask ›"
surface on tvOS) is committed and deployed but **off until two keys exist on
the server**. Nothing else is needed: the code is live, the route simply is
not registered until it can call a model.

## The four environment variables

Set these on the `beach-api` service in the DigitalOcean App Platform UI
(app-level env, `RUN_AND_BUILD_TIME`). `.do/app.yaml` carries placeholders for
reference only — never apply that file blindly (see its header comment).

| Variable | Value | Notes |
|---|---|---|
| `ANTHROPIC_API_KEY` | `sk-ant-…` from console.anthropic.com | **Secret.** Provision in the Anthropic Console → API Keys. Its absence is what keeps the route off today. |
| `CHAT_API_KEY` | any string you choose, e.g. `openssl rand -hex 24` | **Secret.** The shared key the apps present as `X-Chat-Key`. Deliberately separate from `ADMIN_API_KEY` so the admin secret never lives in an app Keychain. This is the one you type into each app. |
| `CHAT_ENABLED` | `true` | Kill switch. `false` removes the route entirely (clients read the 404 as "Ask is switched off"). |
| `CHAT_MODEL` | `claude-opus-5` | Model id the runner uses. Swappable without a redeploy of code — any current Claude model id works; thinking is left at the model's default so older ids don't break. |
| `CHAT_VOICE_MODEL` | `claude-sonnet-5` | Model for *spoken* free-form questions (`voice: true` — Siri, the mic buttons). Faster tier because a listener waits seconds. Optional. |

The route exists only when **`CHAT_ENABLED` is not `false` AND
`ANTHROPIC_API_KEY` is set**. The boot log says which:

```
{"msg":"chat enabled","model":"claude-opus-5","key_configured":true}
{"msg":"chat disabled"}
```

`key_configured` reports whether `CHAT_API_KEY` is set. With it unset the
route exists but answers 503 "chat not configured" — never open.

## Local dev

Same names in `api/.env` (see `api/.env.example`). The Makefile exports them.
Without `ANTHROPIC_API_KEY` in `.env` the local server logs `chat disabled`
and the route is absent, which is why the tool loop is tested against a fake
Messages API rather than the real one.

## Smoke test after the deploy

```sh
curl -s -X POST https://beach.donwb.com/api/v2/chat \
  -H 'X-Chat-Key: <CHAT_API_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","text":"Will Flagler be open Saturday at 2pm?"}]}' | jq
```

Expect `reply` quoting the engine's headline ("Could close around the …
high tide" / "No tide trouble expected" / "Closed until morning"), one
`ramp_outlook` entry in `sources`, and `usage.calls` of 2–3. City questions
("Can I get on the beach in NSB right now?", "Are the Daytona ramps open
Saturday at 2?") answer from `city_now` / `city_outlook` sources with the
per-ramp rows. Then try:

- a follow-up turn (send both prior turns plus the new question),
- "What happened at Flagler yesterday?" → a one-sentence decline (past is out of scope),
- "Which day this weekend is best?" → `weekend_day` sources,
- a wrong key → 401, no header → 401, `CHAT_ENABLED=false` → 404.

Watch the logs for `chat.guard_tripped` — a model reply that promised a
closure or invented a clock time and was corrected or replaced by the
engine's own words. A steady stream of those means the prompt needs work;
an occasional one is the guard doing its job.

## The website (test here first)

`beach.donwb.com` carries an **Ask** section between the weekend outlook and
the live cam (`web/js/ask.js`). On first use it asks for the chat key once
and keeps it in `localStorage` (`beach.chatKey`); "Forget key" under the
transcript clears it, and a 401 clears it too. The three suggested questions
follow the board's selected city ("Can I get on the beach in Daytona Beach
right now?"). A 404 hides the section (feature off). Hard-refresh once after
a deploy — the service worker cache is versioned (`sw.js` CACHE_NAME) but the
old worker serves the old shell until it updates.

## Putting the key into the apps

The apps store `CHAT_API_KEY` in the Keychain, once per device (tvOS has no
iCloud Keychain, so each Apple TV is entered separately).

- **iOS:** tap "Ask about the beach" on the board (or "Ask" on a ramp). The
  key field appears until a key is saved; the question you typed waits in
  the box meanwhile.
- **tvOS:** header "Ask ›". The surface opens on the key field when no key
  is stored; the system keyboard offers dictation and the iPhone keyboard
  prompt. DEBUG builds accept `--surface-chat[=ACCESS_ID] --chat-key <key>`.

A 401 later (rotated key) brings the key field back on both platforms.

The Ask UI is app code, so it needs a **flight after build 33**
(`make flight ARGS="--yes"`) before the App Store / TestFlight builds show it.

## Cost

Roughly two to three model calls per question on `claude-opus-5`, a few
thousand input tokens and a few hundred output tokens — on the order of a
few cents per question. `chat.done` logs `input_tokens` / `output_tokens` /
`calls` per request. There is no rate limit or budget cap: the key is the
gate, and only Don has it.

## Speaking the question

Three ways in, all the same endpoint:

- **The quick path (no model).** The server answers the common spoken shapes
  from the engine's own copy before any model is involved (`chat/route.go`, the pattern router; replies in `chat/quick.go`):
  "can I get on the beach in NSB right now", "are the Daytona ramps open
  Saturday at 2", "which day this weekend is best", and a ramp named outright
  ("is Flagler open right now", "will 27th Ave be open tomorrow at 2"). Sub-second, `model:
  "quick"`, zero usage. Anything the router isn't sure about (a past time,
  "later", a ramp by name, a weekday that is also today) falls through to
  the model. Only first turns are eligible; follow-ups need the conversation.
- **`voice: true`** on the request marks a spoken question: free-form ones
  run on `CHAT_VOICE_MODEL`. Every response carries `spoken` — the reply
  rewritten for text-to-speech (`·` → `.`, `~` → "about", dashes → commas).
- **iOS mic** in the Ask bar (Speech framework, on-device where supported).
  First tap asks for microphone + speech-recognition permission. The
  transcript fills the field live; a 1.4 s pause sends it.
- **Siri** (App Intents + App Shortcuts, `BeachRamp/Intents/AskIntents.swift`).
  Apple requires the app name in every phrase and no free text inside it:
  - "Hey Siri, Beach Info question" (also "Question for Beach Info", "Check the
    beach with Beach Info") → Siri asks "What do you want to know about the
    beach?" → speak → Siri reads the answer. A leading "Ask …" is risky: newer
    iOS treats "Ask ⟨name⟩" as a chat hand-off and answers "can't find the
    ⟨name⟩ app" when there is none, so the "Ask Beach Info …" forms are kept
    only as extras.
  - "Hey Siri, is the beach open in New Smyrna Beach with Beach Info" (city
    is a fixed list: Ponce Inlet, New Smyrna Beach, Daytona Beach Shores,
    Daytona Beach, Ormond Beach).
  - "Hey Siri, is Flagler Avenue open with Beach Info" (ramps are a Siri
    parameter too, `RampIntents.swift`: the roster from the widget snapshot,
    names expanded to their spoken form — "Avenue", "Boulevard" — and
    re-registered at every launch).
  - "Hey Siri, which beach day is best with Beach Info".
  Anything else — a ramp or a time *inside* a free-form sentence after the app
  name ("ask Beach Info if Flagler is open") — cannot match a phrase; Siri then
  tries to search the app's data and says it "doesn't support in-app
  searching". Use the two-step form for those.
  The intent runs in the background with the Keychain key; with no key stored
  it says to open the app and enter it. Phrases register when the app first
  launches after install (and `updateAppShortcutParameters()` runs at every
  launch); they also appear in the Shortcuts app under "Beach Info" — if that
  tile is missing, the metadata never registered. Siri answers to the names in
  `Config/Info-iOS.plist` (`INAlternativeAppNames`: Beach Info, Volusia Beach
  Info, Volusia Beach, Beach Ramp/Ramps) as well as the display name.
- **Apple TV:** select the field, hold the remote's mic button to dictate.
- **Web:** a mic button appears in browsers with the Web Speech API (Safari,
  Chrome); it sends with `voice: true`.
