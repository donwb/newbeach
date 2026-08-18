# Wave Data Pipeline (and its dependency on the cam droplet)

*Written 2026-08-18, the day the wave-aware prediction model shipped and we
discovered NOAA blocks the app's own egress IP.*

## Why this document exists

The tide-closure prediction model is wave-aware: the same tide peak closes
ramps under a wind swell and passes quietly over a flat ocean, so training
and serving both consume significant-wave-height data from NDBC buoy 41113
(Ponce de Leon Inlet). Getting that data into the app turned out to require
a non-obvious dependency: **in production, wave data flows through the
beach-cam relay droplet.** The prediction feature now leans on camera
infrastructure. If you are about to retire, rebuild, or "simplify" the
droplet or its Caddy config, read this first.

## The blocking problem (measured 2026-08-18)

| Client IP | www.ndbc.noaa.gov | coastwatch.pfeg.noaa.gov (ERDDAP) |
|---|---|---|
| Residential (home) | 200 | 200 |
| Cam droplet `68.183.149.152` (DO nyc3) | **403, any user agent** | 200, ~0.6 s |
| App Platform dedicated egress IP | **403, any user agent** | **tarpit — headers never arrive, times out at 30 s** |

- NDBC hard-blocks datacenter IP ranges outright. This started silently: the
  conditions logger shipped 2026-08-16 and its `beach_conditions.wave_height_ft`
  column was NULL in prod from day one — no symptom until the wave model
  needed the data.
- CoastWatch's ERDDAP treats DO IPs inconsistently: the droplet's IP is fine,
  the app's egress IP is tarpitted (three consecutive 30-min snapshots died
  at the client timeout; runtime logs `snapshot: NDBC waves unavailable ...
  Client.Timeout exceeded while awaiting headers`).
- NWS (`api.weather.gov`) lists buoy 41113 but serves `waveHeight: null`, so
  it is not an alternative source.
- **Do not debug "missing prod wave data" by fetching NDBC from a home
  machine.** It will work there and prove nothing — the block is on
  datacenter IPs.

## The pipeline as built

```
                       NDBC realtime2 / stdmet archives   (primary; works from
                                  │                        residential IPs only)
                                  │ 403 from any DO IP
                                  ▼
        CoastWatch ERDDAP (cwwcNDBCMet dataset)           (fallback; same data,
                                  │                        ~30-min lag, full history)
              tarpitted from the app's egress IP
                                  │
                                  ▼
   ┌──────────────────────────────────────────────────────┐
   │  CAM DROPLET  beach-cam-relay  68.183.149.152        │
   │  /etc/caddy/Caddyfile:  handle /erddap/*  →          │
   │      reverse_proxy https://coastwatch.pfeg.noaa.gov  │
   └──────────────────────────────────────────────────────┘
                                  │  https://cams.donwb.com/erddap/...
                                  ▼
   beach-api (App Platform)  — NDBC_ERDDAP_URL env points here in prod
     ├─ conditions logger (30 min): FetchLatestWaves → wave_observations row
     ├─ nightly trainer (03:30 ET): realtime-window heal + archive backfill
     │    (conditions.BackfillWaves) → trains WaveParams from the series
     └─ outlook serve: latest wave_observations row → riskForPeak shift + surf block
```

Every NDBC fetch path (`FetchLatestWaves`, `FetchRealtimeWindow`,
`FetchArchiveMonth` in `api/internal/conditions/ndbc.go`) tries NDBC direct
first, then falls back to the ERDDAP mirror (`erddap.go`). The mirror base
URL honors `NDBC_ERDDAP_URL`; unset, it goes to CoastWatch directly (correct
for local dev and any residential deployment). **Prod sets it to
`https://cams.donwb.com/erddap/tabledap/cwwcNDBCMet.json`** — in the live
app spec (applied via doctl 2026-08-18) and mirrored in the `.do/app.yaml`
reference copy.

## What breaks if the droplet goes away

- Prod wave fetches fall back to... nothing that works from the app's egress
  IP. `wave_observations` stops growing; after `maxWaveAge` (6 h) the outlook
  silently reverts to tide-only (that fallback is by design — no errors, no
  outage, the `surf` block just disappears from `/api/v2/outlook`).
- Cameras break too, obviously — but cameras breaking is *loud*, while the
  wave pipeline starving is *silent*. That asymmetry is the trap this
  document exists to flag.
- The nightly trainer keeps running on whatever history exists; learned
  `WaveParams` persist in `prediction_params`, so serving stays sane. The
  live shift just never sees fresh sea state.

## Runbook

**Is wave data flowing?**
```bash
curl -s https://beach.donwb.com/api/v2/outlook | jq .surf
```
Non-null with a recent `observed_at` = healthy. Null for more than ~an hour
during the day = investigate.

**Is the proxy up?**
```bash
curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" \
  "https://cams.donwb.com/erddap/tabledap/cwwcNDBCMet.json?station,time,wvht,dpd&station=%2241113%22&time%3E=$(date -u -v-6H +%Y-%m-%dT%H%%3A%M%%3A%SZ)"
```
Expect 200 well under 5 s.

**What is the app seeing?** (doctl is authed on the dev Mac)
```bash
doctl apps logs 16a449ad-f635-49e5-8e88-21ac34c583bd --type run | grep -i "wave\|snapshot"
```
The logger warns every 30 min on failure with the exact fetch error; success
is silent at info level (the surf block is the positive signal).

**Restore the Caddy route after a droplet rebuild** (also listed in
CAM-RELAY.md's rebuild section): the `/erddap/*` handle must come before the
catch-all MediaMTX proxy —
```caddyfile
handle /erddap/* {
    reverse_proxy https://coastwatch.pfeg.noaa.gov {
        header_up Host coastwatch.pfeg.noaa.gov
    }
}
```
A dated backup of the pre-change Caddyfile sits next to it on the droplet
(`/etc/caddy/Caddyfile.bak-20260818`).

**If CoastWatch sours on the droplet's IP too** (same class of rot that got
the app's IP): the fallback plan of record is a launchd job on the Mac
Studio that fetches NDBC directly (home IP works for everything) and POSTs
observations to a keyed API endpoint — the `update-stream-url.sh` /
`CAM_HOOK_KEY` pattern. Nothing of that exists yet; build it only when
needed.

## Cross-references

- `CLAUDE.md` → Prediction section ("wave_observations", NDBC-blocks bullet)
  and the env-var table (`NDBC_ERDDAP_URL`, `PREDICT_WAVES_ENABLED`).
- `docs/CAM-RELAY.md` → "ERDDAP wave proxy" row in the runbook table.
- `api/internal/conditions/erddap.go` — the mirror client and the full
  why-comment.
- Backtest fixture regeneration: `api/cmd/gen-waves-fixture` (fetches NDBC
  direct — run it from a residential IP).
