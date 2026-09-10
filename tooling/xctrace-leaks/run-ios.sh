#!/usr/bin/env bash
set -euo pipefail

TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TOOL_DIR/../.." && pwd)"
APP_DIR="$REPO_ROOT/apps/LeakingApp"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  DEVELOPMENT_TEAM="$(
    defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null \
      | awk '/teamID =/ { gsub(/[;\"]/ , "", $3); print $3; exit }' \
      || true
  )"
fi

if [[ -z "$DEVELOPMENT_TEAM" ]]; then
  echo "No Xcode development team found." >&2
  echo "Select a team in Xcode or run with DEVELOPMENT_TEAM=YOUR_TEAM_ID." >&2
  exit 2
fi

export DEVELOPMENT_TEAM
export ALLOW_PROVISIONING_UPDATES="${ALLOW_PROVISIONING_UPDATES:-YES}"
export ENABLE_DEBUG_DYLIB="${ENABLE_DEBUG_DYLIB:-NO}"

DEVICE_ID="${DEVICE_ID:-}"
DEVICE_NAME=""
DEVICE_FILTER="hardwareProperties.platform == 'iOS' AND hardwareProperties.reality == 'physical' AND connectionProperties.pairingState == 'paired' AND connectionProperties.tunnelState == 'connected'"

if [[ -n "$DEVICE_ID" ]]; then
  DEVICE_FILTER="$DEVICE_FILTER AND hardwareProperties.udid == '$DEVICE_ID'"
fi

DEVICES_JSON="$(mktemp -t memory-leak-ios-devices.XXXXXX)"
trap 'rm -f "$DEVICES_JSON"' EXIT

if xcrun devicectl list devices \
  --filter "$DEVICE_FILTER" \
  --json-output "$DEVICES_JSON" \
  --quiet \
  --timeout 10 \
  >/dev/null 2>&1; then
  DEVICE_ID="$(plutil -extract result.devices.0.hardwareProperties.udid raw -o - "$DEVICES_JSON" 2>/dev/null || true)"
  DEVICE_NAME="$(plutil -extract result.devices.0.deviceProperties.name raw -o - "$DEVICES_JSON" 2>/dev/null || true)"
fi

rm -f "$DEVICES_JSON"
trap - EXIT

if [[ -z "$DEVICE_ID" ]]; then
  echo "No connected physical iOS device found." >&2
  echo "Connect, unlock, and trust an iPhone, or set DEVICE_ID explicitly." >&2
  exit 2
fi

if [[ -n "$DEVICE_NAME" ]]; then
  echo "Using connected iOS device: $DEVICE_NAME ($DEVICE_ID)"
else
  echo "Using iOS device: $DEVICE_ID"
fi
echo "Using Xcode development team: $DEVELOPMENT_TEAM"

DESTINATION="platform=iOS,id=$DEVICE_ID"
XCTRACE_DEVICE="$DEVICE_ID"
APP_PROCESS_DEVICE_ID="$DEVICE_ID"
ARTIFACT_BASENAME="iOSDeviceUITestLeakRun"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$APP_DIR/.derived-data}"
APP_BUNDLE_PATH="${APP_BUNDLE_PATH:-$DERIVED_DATA_PATH/Build/Products/Debug-iphoneos/LeakingApp.app}"

export CALLER_DIR="$APP_DIR"
export PROJECT_PATH="$APP_DIR/LeakingApp.xcodeproj"
export SCHEME="LeakingApp"
export DESTINATION
export TEST_IDENTIFIER="LeakingAppUITests/LeakingAppUITests/testRepeatedFlowForInstrumentsAndXctrace"
export APP_PROCESS_NAME="LeakingApp"
export APP_START_WAIT_SECONDS="${APP_START_WAIT_SECONDS:-60}"
export ARTIFACTS_DIR="${ARTIFACTS_DIR:-$APP_DIR/artifacts/xctrace-leaks}"
export ARTIFACT_BASENAME
export DERIVED_DATA_PATH
export APP_BUNDLE_PATH
export XCTRACE_DEVICE
export APP_PROCESS_DEVICE_ID

exec "$TOOL_DIR/run-ui-test-leak-workflow.sh"
