#!/bin/bash
# App Store gallery screenshots — iPhone, iPad, Apple TV, watch.
#
# Builds the Debug app for the simulator, boots the store-size devices,
# launches with the QA sky hooks (--sky-minutes freezes the ground so the
# gallery is reproducible at any hour), and captures raw simctl screenshots
# into design/app-store-screenshots/. No frames, no overlay text — the app
# is the marketing. Live data comes from beach.donwb.com (the sim build
# points at prod), so shoot when the board looks good.
#
# Usage:
#   apple/scripts/screenshots.sh              # every store platform
#   apple/scripts/screenshots.sh iphone ipad  # subset
#   apple/scripts/screenshots.sh --no-build   # reuse the last build
#
# Store sizes (verified after capture):
#   iphone-6.9  1320×2868  iPhone 17 Pro Max
#   ipad-13     2064×2752 / 2752×2064  iPad Pro 13-inch
#   appletv     3840×2160  Apple TV 4K (3rd generation)
#   watch       416×496    Apple Watch Series 11 (46mm)
#
# watchOS notes: status_bar override is not supported on watch sims (the
# clock shows sim time), and the watch app is a companion app — it only
# launches on a watch sim paired to a phone sim carrying the iOS app
# (Xcode's default paired sets cover this).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT="$REPO_ROOT/apple/BeachRamp/BeachRamp.xcodeproj"
DERIVED="$REPO_ROOT/apple/BeachRamp/build/shots-ddata"
OUT_ROOT="$REPO_ROOT/design/app-store-screenshots"

IOS_BUNDLE_ID="com.donwb.BeachRampTV"
# The tvOS app target deliberately shares the iOS bundle ID — that is what
# lets one App Store Connect record carry both platforms (see CLAUDE.md).
TV_BUNDLE_ID="com.donwb.BeachRampTV"
WATCH_BUNDLE_ID="com.donwb.BeachRampTV.watchkitapp"

IPHONE_SIM="iPhone 17 Pro Max"
IPAD_SIM="iPad Pro 13-inch (M5)"
TV_SIM="Apple TV 4K (3rd generation)"
WATCH_SIM="Apple Watch Series 11 (46mm)"

# Sky phases (minutes past midnight for --sky-minutes). Mid-August Volusia:
# sunrise ~06:55, sunset ~19:58.
SKY_DAY=630      # 10:30 — full daylight
SKY_GOLDEN=1170  # 19:30 — golden hour
SKY_DAWN=415     # 06:55 — sunrise

WAIT_SECS="${WAIT_SECS:-14}"   # data + cam settle time after launch
BUILD=1
PLATFORMS=()

for arg in "$@"; do
  case "$arg" in
    --no-build) BUILD=0 ;;
    iphone|ipad|tv|watch) PLATFORMS+=("$arg") ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done
[ ${#PLATFORMS[@]} -eq 0 ] && PLATFORMS=(iphone ipad tv watch)

say() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }

# Pick the UDID for a device name on the newest runtime.
udid_for() {
  xcrun simctl list devices available -j | python3 -c '
import json, sys
name = sys.argv[1]
data = json.load(sys.stdin)["devices"]
best = None
for runtime, devs in data.items():
    ver = runtime.rsplit(".", 1)[-1]  # e.g. iOS-26-5 / watchOS-26-5
    for d in devs:
        if d["name"] == name:
            key = tuple(int(x) for x in ver.split("-")[1:])
            if best is None or key > best[0]:
                best = (key, d["udid"])
if not best:
    sys.exit(f"no available simulator named {name!r}")
print(best[1])
' "$1"
}

boot() { # udid
  xcrun simctl bootstatus "$1" -b >/dev/null
}

launch_and_shoot() { # udid bundle_id outfile [launch args...]
  local udid="$1" bundle="$2" out="$3"; shift 3
  xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1 || true
  xcrun simctl launch "$udid" "$bundle" "$@" >/dev/null
  sleep "$WAIT_SECS"
  xcrun simctl io "$udid" screenshot "$out" >/dev/null
  echo "  $(basename "$out")  $(sips -g pixelWidth -g pixelHeight "$out" 2>/dev/null \
      | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w"x"h}')"
}

build_ios() {
  say "Building BeachRamp (iOS Simulator)"
  xcodebuild -project "$PROJECT" -scheme BeachRamp -configuration Debug \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DERIVED" build -quiet
}

build_tv() {
  say "Building BeachRampTV (tvOS Simulator)"
  xcodebuild -project "$PROJECT" -scheme BeachRampTV -configuration Debug \
    -destination 'generic/platform=tvOS Simulator' \
    -derivedDataPath "$DERIVED" build -quiet
}

build_watch() {
  say "Building BeachRampWatch (watchOS Simulator)"
  xcodebuild -project "$PROJECT" -scheme "BeachRampWatch Watch App" \
    -configuration Debug \
    -destination 'generic/platform=watchOS Simulator' \
    -derivedDataPath "$DERIVED" build -quiet
}

IOS_APP="$DERIVED/Build/Products/Debug-iphonesimulator/BeachRamp.app"
TV_APP="$DERIVED/Build/Products/Debug-appletvsimulator/BeachRampTV.app"
WATCH_APP="$DERIVED/Build/Products/Debug-watchsimulator/BeachRampWatch Watch App.app"

prep_ios_device() { # udid
  boot "$1"
  xcrun simctl status_bar "$1" override --time "9:41" \
    --batteryState charged --batteryLevel 100 \
    --dataNetwork wifi --wifiBars 3 --cellularBars 4 >/dev/null
  xcrun simctl install "$1" "$IOS_APP"
}

shoot_iphone() {
  local udid; udid="$(udid_for "$IPHONE_SIM")"
  say "iPhone — $IPHONE_SIM ($udid)"
  prep_ios_device "$udid"
  local out="$OUT_ROOT/iphone-6.9"; mkdir -p "$out"
  launch_and_shoot "$udid" "$IOS_BUNDLE_ID" "$out/01-board-day.png"    --sky-minutes "$SKY_DAY"
  launch_and_shoot "$udid" "$IOS_BUNDLE_ID" "$out/02-board-golden.png" --sky-minutes "$SKY_GOLDEN"
  launch_and_shoot "$udid" "$IOS_BUNDLE_ID" "$out/03-board-dawn.png"   --sky-minutes "$SKY_DAWN"
}

# The Simulator menu is the only way to rotate an iPad sim: the app's
# --force-landscape hook (requestGeometryUpdate) is silently ignored on
# iPad because the target supports multitasking, and simctl has no rotate
# command. Assumes the device starts portrait; every rotate Left is paired
# with a rotate Right below so runs stay idempotent.
front_ipad_window() {
  osascript >/dev/null <<EOF
tell application "Simulator" to activate
delay 1
tell application "System Events" to tell process "Simulator"
  click (first menu item of menu "Window" of menu bar 1 whose name begins with "$IPAD_SIM")
end tell
EOF
}

rotate_device() { # Left|Right
  osascript >/dev/null <<EOF
tell application "System Events" to tell process "Simulator"
  click menu item "Rotate $1" of menu "Device" of menu bar 1
end tell
EOF
}

shoot_ipad() {
  local udid; udid="$(udid_for "$IPAD_SIM")"
  say "iPad — $IPAD_SIM ($udid)"
  prep_ios_device "$udid"
  local out="$OUT_ROOT/ipad-13"; mkdir -p "$out"
  launch_and_shoot "$udid" "$IOS_BUNDLE_ID" "$out/02-board-portrait.png" \
    --sky-minutes "$SKY_DAY"
  # Wide (the hero): rotate the device, let the board re-lay out, capture.
  # The screenshot buffer stays portrait with rotated content, so
  # counter-rotate to land the store-size 2752×2064.
  open -ga Simulator; sleep 2
  front_ipad_window
  rotate_device Left
  sleep 5
  local wide="$out/01-board-wide.png"
  xcrun simctl io "$udid" screenshot "$wide" >/dev/null
  local w h
  w=$(sips -g pixelWidth  "$wide" | awk '/pixelWidth/{print $2}')
  h=$(sips -g pixelHeight "$wide" | awk '/pixelHeight/{print $2}')
  [ "$w" -lt "$h" ] && sips -r 270 "$wide" >/dev/null
  rotate_device Right
  echo "  $(basename "$wide")  $(sips -g pixelWidth -g pixelHeight "$wide" \
      | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w"x"h}')"
}

# tvOS has no status bar to override and no rotation to fight, so the TV
# gallery is the simplest of the three: boot, install, launch with the QA
# hooks. The camera rail is inline on the board, so the board shot already
# shows the switcher.
#
# NOTE: deliberately no --sky-minutes here. That hook moves the sky, the
# clock, and the sun ribbon, but NOT the verdict subline — ContentView's
# verdict is built from a real Date() — so a frozen evening board reads
# "7:30 PM" next to "9h 1m of light left" and contradicts itself in a store
# screenshot. Shooting at real wall-clock time keeps every string agreeing.
# Shoot midday Eastern: the board is mixed and the cams are lit. (If the
# hook is ever threaded through the verdict, sky phases can come back.)
shoot_tv() {
  local udid; udid="$(udid_for "$TV_SIM")"
  say "Apple TV — $TV_SIM ($udid)"
  boot "$udid"
  xcrun simctl install "$udid" "$TV_APP"
  local out="$OUT_ROOT/appletv"; mkdir -p "$out"
  rm -f "$out"/*.png
  launch_and_shoot "$udid" "$TV_BUNDLE_ID" "$out/01-board.png"
  launch_and_shoot "$udid" "$TV_BUNDLE_ID" "$out/02-outlook.png"  --overlay-outlook
  launch_and_shoot "$udid" "$TV_BUNDLE_ID" "$out/03-activity.png" --overlay-activity
  launch_and_shoot "$udid" "$TV_BUNDLE_ID" "$out/04-weather.png"  --overlay-weather
}

paired_phone_for() { # watch udid -> phone udid
  xcrun simctl list pairs -j | python3 -c '
import json, sys
w = sys.argv[1]
for p in json.load(sys.stdin)["pairs"].values():
    if p["watch"]["udid"] == w:
        print(p["phone"]["udid"]); sys.exit(0)
sys.exit(f"no phone paired with watch {w}")
' "$1"
}

shoot_watch() {
  local wudid pudid
  wudid="$(udid_for "$WATCH_SIM")"
  pudid="$(paired_phone_for "$wudid")"
  say "Watch — $WATCH_SIM ($wudid, companion phone $pudid)"
  # The watch app declares WKCompanionAppBundleIdentifier (no standalone
  # flag), so it only launches on a watch paired to a phone that carries
  # the companion app — boot both and install both.
  boot "$pudid"
  xcrun simctl install "$pudid" "$IOS_APP"
  boot "$wudid"
  local out="$OUT_ROOT/watch"; mkdir -p "$out"
  # Fresh-boot springboard + companion handshake can race the first
  # launch (FBSOpenApplicationServiceErrorDomain) — install + retry.
  local try
  for try in 1 2 3; do
    xcrun simctl install "$wudid" "$WATCH_APP"
    if xcrun simctl launch "$wudid" "$WATCH_BUNDLE_ID" >/dev/null 2>&1; then
      break
    fi
    echo "  launch attempt $try failed; retrying in 5s"
    sleep 5
  done
  sleep "$WAIT_SECS"
  xcrun simctl io "$wudid" screenshot "$out/01-glance.png" >/dev/null
  echo "  01-glance.png  $(sips -g pixelWidth -g pixelHeight "$out/01-glance.png" \
      | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w"x"h}')"
}

# Build once per platform family. The watch also needs the iOS app — its
# companion gets installed on the paired phone.
if [ $BUILD -eq 1 ]; then
  # The iOS build is needed for iphone, ipad, and the watch's companion.
  for p in "${PLATFORMS[@]}"; do
    case "$p" in iphone|ipad|watch) build_ios; break ;; esac
  done
  for p in "${PLATFORMS[@]}"; do
    if [ "$p" = "tv" ]; then build_tv; break; fi
  done
  for p in "${PLATFORMS[@]}"; do
    if [ "$p" = "watch" ]; then build_watch; break; fi
  done
fi

for p in "${PLATFORMS[@]}"; do
  case "$p" in
    iphone) shoot_iphone ;;
    ipad)   shoot_ipad ;;
    tv)     shoot_tv ;;
    watch)  shoot_watch ;;
  esac
done

say "Done — $OUT_ROOT"
