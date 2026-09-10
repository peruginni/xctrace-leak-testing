#!/usr/bin/env bash
set -euo pipefail

TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TOOL_DIR/../.." && pwd)"
APP_DIR="$REPO_ROOT/apps/LeakingApp"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

if [[ -n "${DEVELOPER_DIR:-}" ]]; then
  export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
fi

if ! env -u DEVELOPER_DIR /usr/bin/xcrun --find devicectl >/dev/null 2>&1; then
  echo "Xcode's memory-diagnostic collector cannot find devicectl." >&2
  echo "Check DEVELOPER_DIR or select the full Xcode installation with xcode-select." >&2
  exit 2
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
DEVICE_FILTER="hardwareProperties.platform == 'iOS' AND hardwareProperties.reality == 'physical' AND connectionProperties.pairingState == 'paired'"

if [[ -n "$DEVICE_ID" ]]; then
  DEVICE_FILTER="$DEVICE_FILTER AND hardwareProperties.udid == '$DEVICE_ID'"
fi

DEVICES_JSON="$(mktemp -t memory-diagnostics-ios-devices.XXXXXX)"
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
ARTIFACT_BASENAME="iOSDeviceMemoryDiagnostics"
PROJECT_PATH="$APP_DIR/LeakingApp.xcodeproj"
SCHEME="LeakingApp"
TEST_IDENTIFIER="LeakingAppUITests/LeakingAppUITests/testRepeatedFlowWithXCTestMemoryDiagnostics"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$APP_DIR/.derived-data}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-$APP_DIR/artifacts/xctest-memory-diagnostics}"
RESULT_BUNDLE="$ARTIFACTS_DIR/$ARTIFACT_BASENAME.xcresult"
ATTACHMENTS_DIR="$ARTIFACTS_DIR/$ARTIFACT_BASENAME-attachments"
TEST_LOG="$ARTIFACTS_DIR/$ARTIFACT_BASENAME-xcodebuild.log"

mkdir -p "$ARTIFACTS_DIR"
rm -rf "$RESULT_BUNDLE" "$ATTACHMENTS_DIR"
rm -f "$TEST_LOG"

XCODEBUILD_SETTING_ARGS=(
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
  ENABLE_DEBUG_DYLIB="$ENABLE_DEBUG_DYLIB"
)
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
  XCODEBUILD_SETTING_ARGS+=(CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY")
fi

XCODEBUILD_OPTION_ARGS=()
if [[ "$ALLOW_PROVISIONING_UPDATES" == "YES" ]]; then
  XCODEBUILD_OPTION_ARGS+=(-allowProvisioningUpdates)
fi

echo "[1/3] Running the memory performance UI test..."
set +e
xcodebuild test \
  -quiet \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -parallel-testing-enabled NO \
  -enableCodeCoverage NO \
  -only-testing:"$TEST_IDENTIFIER" \
  -enablePerformanceTestsDiagnostics YES \
  -resultBundlePath "$RESULT_BUNDLE" \
  ${XCODEBUILD_OPTION_ARGS[@]+"${XCODEBUILD_OPTION_ARGS[@]}"} \
  "${XCODEBUILD_SETTING_ARGS[@]}" \
  2>&1 | tee "$TEST_LOG"
XCODEBUILD_STATUS=${PIPESTATUS[0]}
set -e

if [[ "$XCODEBUILD_STATUS" -ge 128 ]]; then
  echo "xcodebuild was interrupted (exit $XCODEBUILD_STATUS)." >&2
  echo "The partial result bundle cannot be inspected. See $TEST_LOG." >&2
  exit "$XCODEBUILD_STATUS"
fi

if [[ ! -f "$RESULT_BUNDLE/Info.plist" ]]; then
  echo "xcodebuild did not finish writing a valid result bundle." >&2
  echo "Expected: $RESULT_BUNDLE/Info.plist" >&2
  echo "See $TEST_LOG." >&2
  exit 2
fi

if [[ "$XCODEBUILD_STATUS" -eq 0 ]]; then
  echo "The performance test completed successfully."
else
  echo "xcodebuild returned status $XCODEBUILD_STATUS; checking its memory graph before deciding the final result."
fi

echo
echo "[2/3] Exporting and checking the post-test memory graph..."
set +e
"$TOOL_DIR/xcleaks.sh" "$RESULT_BUNDLE" "$ATTACHMENTS_DIR"
LEAK_STATUS=$?
set -e

echo
echo "[3/3] Artifacts"
du -sh "$RESULT_BUNDLE" "$ATTACHMENTS_DIR" 2>/dev/null || true
echo "Result bundle: $RESULT_BUNDLE"
echo "Attachments: $ATTACHMENTS_DIR"

case "$LEAK_STATUS" in
  0) echo "Leak check passed." ;;
  1) echo "Leak check failed: leaks were found." ;;
  *) echo "Leak check could not be completed." ;;
esac

exit "$LEAK_STATUS"
