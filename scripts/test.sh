#!/usr/bin/env bash
# Runs the package tests on an iPad simulator (QuakeKit is the scheme Xcode
# generates for the package's library and its tests).
# Usage: scripts/test.sh [iOS]
set -euo pipefail

PLATFORM="${1:-iOS}"
case "$PLATFORM" in
  iOS) FAMILY="^iPad" ;;
  *) echo "Unknown platform $PLATFORM (use iOS)" >&2; exit 1 ;;
esac

newest_runtime() {
  xcrun simctl list runtimes available -j | jq -r --arg platform "$PLATFORM" '
    [.runtimes[] | select(.identifier | test($platform))]
    | sort_by(.version | split(".") | map(tonumber)) | last | .identifier // empty'
}

if [ -z "$(newest_runtime)" ]; then
  echo "No $PLATFORM simulator runtime installed, downloading one"
  xcodebuild -downloadPlatform "$PLATFORM"
fi

UDID=$(xcrun simctl list devices available -j | jq -r --arg platform "$PLATFORM" --arg family "$FAMILY" '
  [.devices | to_entries | sort_by(.key) | reverse | .[]
   | select(.key | test($platform)) | .value[] | select(.name | test($family))]
  | .[0].udid // empty')
if [ -z "$UDID" ]; then
  RUNTIME=$(newest_runtime)
  TYPE=$(xcrun simctl list devicetypes -j | jq -r --arg family "$FAMILY" '
    [.devicetypes[] | select(.name | test($family))] | last | .identifier // empty')
  echo "Creating a $PLATFORM simulator ($TYPE, $RUNTIME)"
  UDID=$(xcrun simctl create "Tests $PLATFORM" "$TYPE" "$RUNTIME")
fi
echo "Testing on $PLATFORM simulator $UDID"

xcodebuild test \
  -scheme QuakeKit \
  -destination "id=$UDID" \
  -derivedDataPath build/test-$PLATFORM \
  CODE_SIGNING_ALLOWED=NO
