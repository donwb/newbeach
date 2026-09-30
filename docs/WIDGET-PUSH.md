# Widget push — reload the Home Screen widget the moment a ramp flips

iOS 26 lets a widget register an APNs push token; a push with
`content-changed` makes WidgetKit reload that widget's timeline right
away, outside its daily refresh budget. Before this, the widget refreshed
on a schedule (`WidgetRefreshPlan`: every 15 min through the driving day)
and could lag a closure by a quarter hour.

## How it flows

1. **The widget extension** (`BeachRampWidgets/WidgetPush.swift`,
   `BeachWidgetPushHandler`, attached with `.pushHandler` on both widget
   configurations) receives a token from WidgetKit and POSTs it to
   `/api/v2/widgets/push-token` as `{token: hex, environment}`. Xcode
   builds say `sandbox`, TestFlight/App Store builds say `production`.
   The extension carries the `aps-environment` entitlement for this.
2. **The API** stores one row per token (`widget_push_tokens`, migration
   014). Unauthenticated on purpose: the extension holds no key, and a
   stray registration only earns a harmless push.
3. **The ingester** calls the notifier on every ramp status flip
   (`Ingester.SetStatusChangeHook`, fired right after the history row is
   written).
4. **The notifier** (`api/internal/widgetpush`) coalesces: a run 5 s
   after the first flip (one GIS poll can flip several ramps), runs at
   least 60 s apart. It sends `{"aps":{"content-changed":true}}` with
   `apns-push-type: widgets` to topic `com.donwb.BeachRampTV.push-type.widgets`
   over HTTP/2 with a token-authenticated (ES256 JWT, cached 50 min) APNs
   client — no third-party library. A 410 / `BadDeviceToken` /
   `Unregistered` deletes the row; other failures are logged and retried
   on the next flip.

Devices on iOS 18 never register a token and keep the timed plan.

## Server setup (once)

1. Apple Developer → Certificates, Identifiers & Profiles → **Keys** →
   create a key with **Apple Push Notifications service (APNs)**. Download
   the `.p8` (only offered once), note the **Key ID**. The team id is
   `YR2B55YA56`.
2. Set in the App Platform UI: `APNS_KEY_ID`, `APNS_KEY_P8` (paste the whole
   PEM; literal `\n` sequences are fine), `APNS_TEAM_ID`, `APNS_BUNDLE_ID`
   (`com.donwb.BeachRampTV`), `WIDGET_PUSH_ENABLED=true`.
3. Boot log says `widget push enabled` with the topic, or
   `widget push disabled` / `bad APNs config`.

The **Push Notifications capability** must be on the widget extension's
App ID (`com.donwb.BeachRampTV.widgets`). Automatic signing normally adds it
when the entitlement appears; if a flight fails at signing with a
provisioning-profile / entitlement mismatch, enable Push Notifications on
that identifier in the developer portal and re-run the flight.

## Verifying

```sh
# tokens registered (after the widget has been on a Home Screen on iOS 26)
curl -s -H 'X-Api-Key: <ADMIN_API_KEY>' -X POST https://beach.donwb.com/api/v2/admin/widgets/push | jq
# → {"sent": n, "dropped": 0, "failed": 0, "registered": n}
```

`sent > 0` and the widget visibly reloading (the clock in its header moves)
proves the pipeline. Then watch a real flip: the county changes a status,
the ingester logs `ramp status changed`, `widgetpush` logs `widget push`,
and the widget follows within seconds. `dropped` means APNs rejected a
token (uninstalled, or sandbox/production mismatch — a Debug build's
sandbox token pushed through production, or vice versa; the environment
column is set by the build, so a device that switches between an Xcode
build and TestFlight re-registers correctly on its next token change).

## Limits and notes

- WidgetKit may still throttle pushes it considers excessive; the notifier's
  60 s floor keeps a flapping ramp from spamming.
- Pushes carry no content — the widget fetches on reload — so nothing
  sensitive travels through APNs.
- The same APNs client is the plumbing the backlog's Live Activity sender
  needs (different push type and topic suffix).
