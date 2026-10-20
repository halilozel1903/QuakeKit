#!/usr/bin/env bash
# Captures README screenshots of the example app on an iPad simulator.
# Usage: scripts/screenshots-ipad.sh <Scheme> <bundle id> <scene> [<scene> ...]
# Writes docs/screenshots/ipad-<scene>.png, for example ipad-map.png.
#
# Every scene loads live data from the USGS feeds and FDSN event service at earthquake.usgs.gov
# and live Apple Maps tiles. The app writes tmp/screenshot-ready into its container once the data
# is on screen and the map has had 12 s to draw; the script waits for that marker and exits with an error instead of
# keeping a blank, stale, home-screen or error-screen capture.
set -euo pipefail

SCHEME="$1"; BUNDLE_ID="$2"; shift 2
SCENES=("$@")
if [ ${#SCENES[@]} -eq 0 ]; then
  echo "No scenes given" >&2
  exit 1
fi
OUT="docs/screenshots"
MIN_BYTES=150000
mkdir -p "$OUT"

# Newest iOS runtime, used only when a simulator has to be created.
RUNTIME=$(xcrun simctl list runtimes available -j | jq -r '
  [.runtimes[] | select(.identifier | test("iOS"))]
  | sort_by(.version | split(".") | map(tonumber)) | last | .identifier // empty')

# pick_ipad <preferred name pattern> ...
# Prints the UDID of an available iPad simulator on the newest iOS runtime, preferring the first
# pattern that matches. Creates one when none exists.
pick_ipad() {
  local devices udid pattern type
  devices=$(xcrun simctl list devices available -j | jq -c '
    [.devices | to_entries | sort_by(.key) | reverse | .[]
     | select(.key | test("iOS")) | .value[] | select(.name | test("^iPad"))]')
  for pattern in "$@"; do
    udid=$(jq -r --arg pattern "$pattern" 'map(select(.name | test($pattern))) | .[0].udid // empty' <<< "$devices")
    if [ -n "$udid" ]; then echo "$udid"; return; fi
  done
  udid=$(jq -r '.[0].udid // empty' <<< "$devices")
  if [ -z "$udid" ]; then
    type=$(xcrun simctl list devicetypes -j | jq -r '
      [.devicetypes[] | select(.name | test("^iPad Pro"))] | last | .identifier // empty')
    if [ -z "$type" ] || [ -z "$RUNTIME" ]; then
      echo "No iPad simulator, device type or iOS runtime available" >&2
      exit 1
    fi
    udid=$(xcrun simctl create "Screenshots iPad" "$type" "$RUNTIME")
  fi
  echo "$udid"
}

IPAD=$(pick_ipad "^iPad Pro 13" "^iPad Pro" "^iPad Air 13" "^iPad Air")
echo "Using iPad simulator $IPAD"

xcodebuild build \
  -project "Example/$SCHEME.xcodeproj" \
  -scheme "$SCHEME" \
  -destination "id=$IPAD" \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= | tail -n 5

APP=$(find build/Build/Products -maxdepth 2 -name "$SCHEME.app" -path "*iphonesimulator*" | head -n 1)
if [ -z "$APP" ]; then
  echo "Build product $SCHEME.app not found" >&2
  exit 1
fi

# valid_capture <file> <previous capture or empty>
# A blank frame (app still launching) compresses to a small PNG, and a capture identical to the
# previous scene means the app never switched scenes.
valid_capture() {
  local file="$1" previous="$2"
  [ -s "$file" ] || return 1
  [ "$(wc -c < "$file")" -gt "$MIN_BYTES" ] || return 1
  sips -g pixelWidth "$file" > /dev/null 2>&1 || return 1
  if [ -n "$previous" ] && cmp -s "$file" "$previous"; then
    return 1
  fi
  return 0
}

xcrun simctl shutdown all > /dev/null 2>&1 || true
xcrun simctl boot "$IPAD" || true
xcrun simctl bootstatus "$IPAD" -b
xcrun simctl status_bar "$IPAD" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3
xcrun simctl ui "$IPAD" appearance dark
xcrun simctl install "$IPAD" "$APP"
CONTAINER=$(xcrun simctl get_app_container "$IPAD" "$BUNDLE_ID" data)

# System banners (such as "Ready for Apple Intelligence") appear shortly after a first boot.
# Launch the app once and let them come and go before capturing anything.
xcrun simctl launch "$IPAD" "$BUNDLE_ID" > /dev/null 2>&1 || true
sleep 45
xcrun simctl terminate "$IPAD" "$BUNDLE_ID" 2>/dev/null || true
# Give the home screen time to settle, then keep a capture of it so a frame where the app never
# came to the front is rejected.
sleep 15
HOME_SHOT="$OUT/.home-ipad.png"
xcrun simctl io "$IPAD" screenshot "$HOME_SHOT"

previous=""
for scene in "${SCENES[@]}"; do
  file="$OUT/ipad-$scene.png"
  ok=""
  for attempt in 1 2 3; do
    xcrun simctl terminate "$IPAD" "$BUNDLE_ID" 2>/dev/null || true
    sleep 1
    rm -f "$CONTAINER/tmp/screenshot-ready"
    if ! xcrun simctl launch "$IPAD" "$BUNDLE_ID" -screenshot "$scene"; then
      echo "Could not launch the app for ipad-$scene (attempt $attempt), retrying"
      continue
    fi
    # The app writes this marker once the data is on screen and the map has had time to draw.
    waited=0
    while [ ! -f "$CONTAINER/tmp/screenshot-ready" ] && [ "$waited" -lt 150 ]; do
      sleep 1
      waited=$((waited + 1))
    done
    if [ ! -f "$CONTAINER/tmp/screenshot-ready" ]; then
      echo "The app did not show $scene with its live data (attempt $attempt), retrying"
      continue
    fi
    # Let the last map tiles and transitions settle.
    sleep $((3 + attempt * 2))
    rm -f "$file"
    xcrun simctl io "$IPAD" screenshot "$file"
    if valid_capture "$file" "$previous" && ! cmp -s "$file" "$HOME_SHOT"; then
      ok=1
      break
    fi
    echo "Blank or stale capture for ipad-$scene, retrying"
  done
  if [ -z "$ok" ]; then
    echo "Capture for ipad-$scene failed; refusing to commit a broken screenshot." >&2
    rm -f "$file" "$HOME_SHOT"
    exit 1
  fi
  previous="$file"
  echo "Captured $file ($(wc -c < "$file") bytes)"
done

rm -f "$HOME_SHOT"
xcrun simctl shutdown "$IPAD" || true
