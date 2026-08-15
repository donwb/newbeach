#!/bin/bash
# flight.sh — archive the iOS and tvOS apps and upload both to TestFlight.
#
# Deliberately separate from the commit/push/test loop: flighting is an
# explicit, bandwidth-heavy act you kick off when you're on a real link.
# DON RUNS THIS — it is not something an agent does to finish a task.
#
#   apple/scripts/flight.sh                 bump build number, archive, upload both
#   apple/scripts/flight.sh --build 12      flight as a specific build number
#   apple/scripts/flight.sh --no-bump       flight the number already in Version.xcconfig
#   apple/scripts/flight.sh --yes           skip the interactive confirmations
#   apple/scripts/flight.sh --ios-only      iOS archive only
#   apple/scripts/flight.sh --tv-only       tvOS archive only
#   apple/scripts/flight.sh --archive-only  archive but do NOT upload (dry run)
#
# What it does:
#   1. sanity checks (repo root, clean-ish tree, API hostname tripwire)
#   2. bumps CURRENT_PROJECT_VERSION in apple/BeachRamp/Config/Version.xcconfig
#      (single source of truth — one number covers every target)
#   3. xcodebuild archive (iOS device + tvOS, Release)
#   4. exportArchive with destination=upload → App Store Connect. Both
#      platforms land on the SAME com.donwb.BeachRampTV app record.
#   5. tags the commit flight/build-N
#
# Auth: uses the Apple ID session Xcode is signed into (same as Organizer
# uploads). To try an App Store Connect API key instead, set ASC_KEY_ID,
# ASC_ISSUER_ID, ASC_KEY_PATH — but see the warning below, it does not
# currently work for the export step.
#
# ⚠️  Stale Apple ID session is the #1 failure mode. The export step re-signs
#     with cloud-managed distribution signing, which ONLY the Apple ID session
#     can do. Symptoms are misleading: "Failed to Use Accounts", keychain
#     "missing Xcode-Username", or "App Store Connect access for YR2B55YA56 is
#     required" in xcdistributionlogs. Xcode's Accounts pane LIES — it shows
#     signed-in while dead, and opening it does not refresh. Fix: remove the
#     Apple ID with the − button and re-add with password/2FA, at the Mac, not
#     over a remote session. The archive survives, so recovery is just:
#         apple/scripts/flight.sh --no-bump --yes
set -euo pipefail

cd "$(dirname "$0")/../.."
PROJECT="apple/BeachRamp/BeachRamp.xcodeproj"
XCCONFIG="apple/BeachRamp/Config/Version.xcconfig"
APICLIENT="apple/BeachRamp/BeachStatus/Sources/BeachStatus/Networking/APIClient.swift"
[[ -d "$PROJECT" ]] || { echo "flight: must run from the newbeach repo ($PROJECT not found)" >&2; exit 1; }

BUILD_ARG=""
BUMP=1
ASSUME_YES=0
DO_IOS=1
DO_TV=1
UPLOAD=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --build)        BUILD_ARG="$2"; shift 2 ;;
    --no-bump)      BUMP=0; shift ;;
    --yes|-y)       ASSUME_YES=1; shift ;;
    --ios-only)     DO_TV=0; shift ;;
    --tv-only)      DO_IOS=0; shift ;;
    --archive-only) UPLOAD=0; shift ;;
    *) echo "flight: unknown option $1" >&2; exit 1 ;;
  esac
done

confirm() {
  [[ $ASSUME_YES -eq 1 ]] && return 0
  read -r -p "$1 [y/N] " reply
  [[ "$reply" == "y" || "$reply" == "Y" ]]
}

# --- 1. Sanity checks -------------------------------------------------------

if [[ -n "$(git status --porcelain)" ]]; then
  echo "⚠️  Working tree is dirty — the flighted build won't match any commit."
  confirm "Flight anyway?" || exit 1
fi

# The apps talk to a hardcoded base URL. Shipping a binary still pointed at the
# DigitalOcean default hostname instead of the custom domain is a one-way
# mistake once it's in review, so stop and make it deliberate.
if grep -q 'ondigitalocean\.app' "$APICLIENT" 2>/dev/null; then
  echo "⚠️  $APICLIENT still points at the DigitalOcean hostname:"
  grep -n 'ondigitalocean\.app' "$APICLIENT" | sed 's/^/     /'
  echo "   Production is https://beach.donwb.com — a submitted binary would ship the DO URL."
  confirm "Ship it pointed at the DigitalOcean hostname anyway?" || exit 1
fi

# --- 2. Build number --------------------------------------------------------

CURRENT=$(grep -m1 '^CURRENT_PROJECT_VERSION' "$XCCONFIG" | awk -F' = ' '{print $2}')
if [[ -n "$BUILD_ARG" ]]; then
  BUILD="$BUILD_ARG"
elif [[ $BUMP -eq 1 ]]; then
  BUILD=$((CURRENT + 1))
else
  BUILD="$CURRENT"
fi
if [[ "$BUILD" != "$CURRENT" ]]; then
  sed -i '' -E "s/^(CURRENT_PROJECT_VERSION = ).*/\1$BUILD/" "$XCCONFIG"
  echo "$XCCONFIG: build $CURRENT → $BUILD (commit this with your next commit)"
fi

VERSION=$(grep -m1 '^MARKETING_VERSION' "$XCCONFIG" | awk -F' = ' '{print $2}')
echo "Flighting Beach Ramps $VERSION ($BUILD)…"

# --- 3+4. Archive + export per platform -------------------------------------

AUTH_ARGS=()
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_KEY_PATH:-}" ]]; then
  AUTH_ARGS=(-authenticationKeyID "$ASC_KEY_ID"
             -authenticationKeyIssuerID "$ASC_ISSUER_ID"
             -authenticationKeyPath "$ASC_KEY_PATH")
fi

flight_one() {  # scheme destination archive_path export_path
  local scheme="$1" dest="$2" archive="$3" export_path="$4"
  echo "── $scheme: archiving…"
  xcodebuild -project "$PROJECT" -scheme "$scheme" \
    -destination "$dest" \
    -archivePath "$archive" \
    -allowProvisioningUpdates -quiet archive
  if [[ $UPLOAD -eq 0 ]]; then
    echo "── $scheme: archived to $archive (--archive-only, not uploading)"
    return 0
  fi
  echo "── $scheme: uploading…"
  xcodebuild -exportArchive \
    -archivePath "$archive" \
    -exportOptionsPlist apple/scripts/ExportOptions.plist \
    -exportPath "$export_path" \
    -allowProvisioningUpdates "${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"}"
}

if [[ $DO_IOS -eq 1 ]]; then
  flight_one BeachRamp 'generic/platform=iOS' \
    "build/flight/BeachRamp-$BUILD.xcarchive" "build/flight/export-ios-$BUILD"
fi
if [[ $DO_TV -eq 1 ]]; then
  flight_one BeachRampTV 'generic/platform=tvOS' \
    "build/flight/BeachRampTV-$BUILD.xcarchive" "build/flight/export-tv-$BUILD"
fi

# --- 5. Mark it -------------------------------------------------------------

PLATFORMS=""
[[ $DO_IOS -eq 1 ]] && PLATFORMS="iOS"
[[ $DO_TV -eq 1 ]] && PLATFORMS="${PLATFORMS:+$PLATFORMS + }tvOS"

if [[ $UPLOAD -eq 0 ]]; then
  echo "✅ Build $BUILD ($PLATFORMS) archived — nothing uploaded (--archive-only)."
  exit 0
fi

git tag -f "flight/build-$BUILD"
echo "✅ Build $BUILD ($PLATFORMS) uploaded — App Store Connect is processing it."
echo "   Both platforms land on the one com.donwb.BeachRampTV record."
echo "   Tagged flight/build-$BUILD (local; push tags whenever)."
[[ "$BUILD" != "$CURRENT" ]] && echo "   Don't forget: commit the $XCCONFIG bump."
exit 0
