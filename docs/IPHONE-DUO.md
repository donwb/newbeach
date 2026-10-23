# iPhone Duo upgrade — playbook for any of Don's iOS apps

Written 2026-10-23 (Duo launch day) after taking Volusia Beach Info from "never heard of
it" to a Duo-ready TestFlight build (1.4 (46)) in one session. Earlier groundwork:
Refrain's day-one spike and pose walk (bkmks `design/PRD-v2.md`, commits af2e9a1,
43430b7; Xcode 27.1 **beta 1**). Where this doc and Refrain's notes disagree, this one
was measured on the **release** 27.1 runtime.

Copyable code from this repo:
- `apple/BeachRamp/BeachRamp/Views/LayoutProbe.swift`: a DEBUG `--layout-probe` launch arg
  that logs size classes, safe-area insets, reserved regions and hinge changes.
- `apple/BeachRamp/BeachRamp/Views/Board/FoldSeam.swift`: finds the hinge's x position and
  tracks the hinge state, with the compile-time gate already in place.

## 1. Why an app needs a rebuild at all

The binary's **SDK linkage** decides how the Duo presents it:

| Linked against | On the Duo |
|---|---|
| iOS 27.0 SDK or older | **Compatibility mode**: a black strip down the trailing edge for the clock and status icons, the app boxed into the rest with its own rounded corners, and a `TabView` keeps its horizontal bottom bar. Usable, but visibly "not updated". |
| iOS 27.1 SDK | Edge-to-edge. The background runs under the system strip, and a `TabView` moves into a **vertical rail** inside that strip. |

So step one is always: **build with the Xcode 27.1 release**. Layout fixes come after.

## 2. Toolchain

- **Xcode 27.1 release is 27A9275.** The flight tool rejects any build version ending in a
  lowercase letter (a beta), so an RC or beta can't upload. Check with
  `DEVELOPER_DIR=… xcodebuild -version`.
- **Install it beside the existing Xcode, don't replace it.** On the Studio it landed as
  `/Applications/Xcode copy.app` (Don kept `Xcode.app`, 26.3). Leave `xcode-select` alone.
- **The shared `flight` tool calls plain `xcodebuild`, so `DEVELOPER_DIR` steers it.** No
  sudo needed:
  ```sh
  DEVELOPER_DIR="/Applications/Xcode copy.app/Contents/Developer" make flight ARGS="--only ios --yes"
  ```
  `flight` prints `xcode-select -p` as "at …", which then shows the *old* path. The
  version and build it prints are the real ones; only that path is misleading.
- **Check the archive, not the log:**
  ```sh
  /usr/libexec/PlistBuddy -c 'Print :DTSDKName' -c 'Print :DTXcodeBuild' \
    build/flight/<App>-<N>.xcarchive/Products/Applications/<App>.app/Info.plist
  # → iphoneos27.1 / 27A9275
  ```
- **Gate fold code so older Xcodes still build.** All fold APIs are
  `@available(anyAppleOS 27.1, *)`, and `#available` doesn't stop the compiler from
  needing the symbols. Use the SwiftUICore module version:
  `#if canImport(SwiftUICore, _version: 8.0.85)`. 27.1 ships 8.0.85, 26.2's SDK ships
  7.2.5, and 27.0 is 8.0.84. `compiler(>=6.4)` can't separate 27.0 from 27.1.
- **The 27.1 SDK adds warnings.** Beach got one new "expression is 'async' but is not
  marked with 'await'" (an error only in Swift 6 language mode). Expect a few per app.
- **tvOS and watchOS SDKs in Xcode 27.1 are 27.0.** Nothing Duo-specific there, but if you
  flight tvOS from 27.1 it moves to the 27 SDK too. Beach flighted iOS only.

## 3. Simulator gotchas (each one cost time)

1. **The runtime is installed but `simctl list runtimes` doesn't show it.** A stale
   `CoreSimulatorService` from before the install is still running. Check
   `/Library/Developer/CoreSimulator/Images/images.plist` for `SimRuntime.iOS-27-1`. If
   it's there, the service is stale. The fix is
   `killall -9 com.apple.CoreSimulator.CoreSimulatorService` (it respawns), **but that
   shuts down every booted simulator on the Mac, including other sessions'**. Check
   first: `xcrun simctl list devices booted`, and `ps` for other `claude` / `xcodebuild`
   processes. On 10/23 this interrupted a Fan on the Side session's run.
2. **Don't share the Duo simulator between repos.** Several sessions run on the Studio at
   once, and one app's `make` relaunched its own app over ours. Create one per app:
   ```sh
   xcrun simctl create "iPhone Duo (<App>)" com.apple.CoreSimulator.SimDeviceType.iPhone-Duo \
     com.apple.CoreSimulator.SimRuntime.iOS-27-1
   ```
3. **Screenshots need a display.** Plain `simctl io screenshot` captures the inner screen,
   which is **black while the device is closed**. Get the UUIDs from
   `xcrun simctl io <dev> enumerate`: the outer screen is 1398×2034 px (466×678 pt @3x),
   the inner 2007×2853 px. Then use
   `xcrun simctl io <dev> screenshot --display=<uuid> out.png`.
4. **Only a human can change the pose.** `simctl` has no fold or rotate command, and
   `simctl io screenConfig --display=<outer> power off` does **not** unfold the device
   (the hinge stays `closed`). Ask Don to change it in Xcode's Device Hub, naming the
   simulator. A walk is three requests: open flat, tap whatever needs checking, rotate.
   Everything else (build, install, launch, screenshot, read the probe) runs headless.
5. **Read the probe with a console launch:**
   `xcrun simctl launch --console-pty --terminate-running-process <dev> <bundle-id> --layout-probe > probe.log &`.
   Keep it running while Don changes poses; each change logs a line.

## 4. What the app is handed: the measured geometry

Release 27.1 runtime, Beach (no `TabView`, `NavigationStack` root):

| Pose | Size classes | View size (pt) | Safe-area insets | Reserved regions |
|---|---|---|---|---|
| Closed (outer screen) | compact × regular | 382×644 of 466×678 | trailing 84, bottom 34 | occlusion: camera 37×37 @ (399,29), status strip 84×174 @ (382,0) |
| Open flat, hinge vertical ("book") | **regular × regular** | 867×635 of 951×669 | trailing 84, bottom 34 | **division** x 455–495, full height, `isActive=false` while flat, margins l/r 20 |
| Open, rotated (hinge horizontal) | **regular × regular** | 669×917 of 669×951 | bottom 34 only | **division** y 455–495, full width; status 144×82 top-right shows during the rotation, then hides like iPhone landscape |

Findings that differ from Refrain's beta-1 notes:
- **`reservedRegions(kind: .division)` now returns the hinge.** In beta 1 it returned
  nothing. It reports `isActive == false` while the device is flat, so query with
  `options: [.includeInactive]` or you get an empty array.
- **`onHingeChange` fires at launch** (`nil → closed`, or `nil → fullyOpen` on a cold start
  in the open pose), so you get the starting state without waiting for a fold. While a
  fold is in progress it fires many times in a row with the same `.partiallyOpen` status,
  so dedupe before acting. There's no hinge angle, only `.closed` / `.partiallyOpen` /
  `.fullyOpen`.
- Rotated, Refrain (with a `TabView`) saw a **top inset of 82**. Beach saw none, with the
  status as an occlusion region instead. Run your own probe rather than trusting either.
- **The book's pages are uneven.** The hinge is at x=475 of 951, but the trailing 84 pt
  belong to the system strip, so the left page is 475 pt and the right page ~392 pt.
  Center on the **screen**, never the safe area: the safe area's midpoint (433) puts the
  split 42 pt off the hinge.

## 5. Audit checklist: what actually broke in Beach

1. **Any `horizontalSizeClass == .regular` branch now runs on a phone.** Both open poses
   are regular × regular, so your iPad layout ships on the Duo. Beach's iPad board
   appeared in the book pose; the rotated pose got its portrait arrangement. List every
   size-class switch and decide what each pose should get.
2. **Fixed frames sized for an iPad overflow.** Beach's ramp detail was a hand-drawn
   760×762 panel: taller than the book pose (669) *and* wider than the rotated pose (669).
   Search for big constants (`grep -nE "frame\(width: [0-9]{3}"`) and clamp each one to its
   container: `min(760, geo.size.width - 32)`.
3. **Splits must sit on the hinge.** A landscape split at a fixed ratio (Beach: 60.8%
   headline / stats, and a 372 pt rail) lands its edge within a few points of the fold.
   Anchor the split on the seam: left column width = `seam − leading padding − gap/2`,
   and let the right column fill the rest. Grids on the ~420 pt left page want iPhone
   column counts (Beach went from 3 to 2).
4. **Text sized for iPad cells wraps on the narrow right page.** "71° · 77°" broke onto
   two lines in a ~95 pt cell. Use `.lineLimit(1).minimumScaleFactor(0.7)` on short values.
5. **Scrolling content passing over the hinge is fine.** Single-column scroll views in the
   rotated pose were left alone, and so was a horizontally scrolling tab strip in the
   book pose. Only fixed, non-scrolling layout needs to avoid the fold.
6. **Closed is roughly iPhone-mini width (382 pt).** Usually fine if the app already
   handles compact phones. Check large Dynamic Type there.

## 6. The order that worked

1. Confirm Xcode 27.1 (27A9275) is installed and its iOS 27.1 runtime is visible to
   `simctl` (gotcha 3.1).
2. Build against 27.1 with `-destination 'generic/platform=iOS Simulator'` to catch
   compile errors.
3. Read the app's size-class branches and fixed frames against §4's table to predict what
   breaks, before any simulator time.
4. Add the probe plus the seam code, build, and install on your own Duo simulator.
5. Walk the poses with Don: closed (screenshot the outer display), open flat, tap into
   detail screens, rotate. Fix, reinstall, and re-screenshot the same pose. Relaunching
   doesn't change the pose.
6. Check the build still passes on the old Xcode (the gate), commit, flight iOS from 27.1,
   then confirm the archive's `DTSDKName`.
7. On real hardware: the book pose's splits, a detail screen, the closed screen. The
   simulator can't show how the fold looks in hand.
