#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEAK_DETECTOR_DIR="$APP_DIR/../../leak-detector"
IOS_TARGET="${IOS_TARGET:-device}"

case "$IOS_TARGET" in
  device)
    DEVICE_ID="${DEVICE_ID:-}"
    if [[ -z "$DEVICE_ID" ]]; then
      DEVICES_JSON="$(mktemp -t memory-leak-ios-devices.XXXXXX)"
      trap 'rm -f "$DEVICES_JSON"' EXIT
      if xcrun devicectl list devices \
        --filter "hardwareProperties.platform == 'iOS' AND deviceProperties.bootState == 'booted' AND connectionProperties.pairingState == 'paired'" \
        --json-output "$DEVICES_JSON" \
        --quiet \
        --timeout 10 \
        >/dev/null 2>&1; then
        DEVICE_ID="$(plutil -extract result.devices.0.hardwareProperties.udid raw -o - "$DEVICES_JSON" 2>/dev/null || true)"
      fi
      rm -f "$DEVICES_JSON"
      trap - EXIT
    fi

    if [[ -z "$DEVICE_ID" ]]; then
      echo "No connected physical iOS device found. Connect, unlock, and trust a device, or set DEVICE_ID explicitly." >&2
      exit 2
    fi

    DESTINATION="platform=iOS,id=$DEVICE_ID"
    XCTRACE_DEVICE="$DEVICE_ID"
    APP_PROCESS_DEVICE_ID="$DEVICE_ID"
    ARTIFACT_BASENAME="iOSDeviceUITestLeakRun"
    ;;
  simulator)
    SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17 Pro}"
    SIMULATOR_ID="${SIMULATOR_ID:-$(xcrun simctl list devices available | awk -v name="$SIMULATOR_NAME" '
      {
        line=$0
        sub(/^[[:space:]]+/, "", line)
        if (index(line, name " (") == 1) {
          id=substr(line, length(name) + 3)
          sub(/\).*$/, "", id)
          print id
        }
      }
    ' | tail -n 1)}"

    if [[ -z "$SIMULATOR_ID" ]]; then
      echo "Could not find an available simulator named '$SIMULATOR_NAME'." >&2
      exit 2
    fi

    xcrun simctl boot "$SIMULATOR_ID" >/dev/null 2>&1 || true
    open -a Simulator --args -CurrentDeviceUDID "$SIMULATOR_ID"
    xcrun simctl bootstatus "$SIMULATOR_ID" -b

    DESTINATION="platform=iOS Simulator,id=$SIMULATOR_ID"
    XCTRACE_DEVICE="$SIMULATOR_ID"
    APP_PROCESS_DEVICE_ID=""
    ARTIFACT_BASENAME="iOSSimulatorUITestLeakRun"
    ;;
  *)
    echo "IOS_TARGET must be 'device' or 'simulator'." >&2
    exit 2
    ;;
esac

export CALLER_DIR="$APP_DIR"
export PROJECT_PATH="$APP_DIR/MemoryLeakingApp_iOS.xcodeproj"
export SCHEME="MemoryLeakingApp_iOS"
export DESTINATION
export TEST_IDENTIFIER="MemoryLeakingApp_iOSUITests/MemoryLeakingApp_iOSUITests/testOpenAndCloseLeakingScreenRepeatedly"
export APP_PROCESS_NAME="MemoryLeakingApp_iOS"
export APP_START_WAIT_SECONDS="${APP_START_WAIT_SECONDS:-60}"
export ARTIFACT_BASENAME
export XCTRACE_DEVICE
export APP_PROCESS_DEVICE_ID

exec "$LEAK_DETECTOR_DIR/run-ui-test-leak-workflow.sh"
