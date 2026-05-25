#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/rezka-player.xcodeproj"
SCHEME="rezka-player"
BUNDLE_ID="com.dsoft.rezka-player"
DEFAULT_DEVICE_NAME="Apple TV 4K (3rd generation)"
DEVICE_QUERY="${1:-$DEFAULT_DEVICE_NAME}"

DEVICE_ID="$(
  xcrun simctl list devices available | \
    grep -F "$DEVICE_QUERY" | \
    sed -n 's/.*(\([0-9A-F-][0-9A-F-]*\)).*/\1/p' | \
    head -n 1
)"

if [[ -z "$DEVICE_ID" ]]; then
  echo "Could not find simulator device: $DEVICE_QUERY"
  exit 1
fi

"$ROOT_DIR/scripts/simulator_proxy.sh" ensure

xcrun simctl boot "$DEVICE_ID" >/dev/null 2>&1 || true
xcrun simctl spawn "$DEVICE_ID" launchctl setenv REZKA_SIMULATOR_PROXY 1

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "id=$DEVICE_ID" \
  build >/dev/null

APP_PATH="$(
  find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path "*/Build/Products/Debug-appletvsimulator/rezka-player.app" \
    | grep -v '/Index\.noindex/' \
    | head -n 1
)"

if [[ -z "$APP_PATH" ]]; then
  echo "Build finished, but app path was not found in DerivedData."
  exit 1
fi

xcrun simctl install "$DEVICE_ID" "$APP_PATH"
xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID"

if ! xcrun simctl get_app_container "$DEVICE_ID" "$BUNDLE_ID" groups | grep -q "group.com.dsoft.rezka-player"; then
  echo "warning: app group 'group.com.dsoft.rezka-player' is unavailable in this build"
fi

"$ROOT_DIR/scripts/simulator_proxy.sh" ensure

open -a Simulator

echo "Launched $BUNDLE_ID on $DEVICE_QUERY ($DEVICE_ID)"
