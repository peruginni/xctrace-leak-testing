#!/usr/bin/env bash
set -euo pipefail

LEAK_DETECTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CALLER_DIR="${CALLER_DIR:-$PWD}"

PROJECT_PATH="${PROJECT_PATH:-}"
WORKSPACE_PATH="${WORKSPACE_PATH:-}"
SCHEME="${SCHEME:-}"
DESTINATION="${DESTINATION:-platform=macOS}"
TEST_IDENTIFIER="${TEST_IDENTIFIER:-}"
APP_PROCESS_NAME="${APP_PROCESS_NAME:-}"
APP_PROCESS_DEVICE_ID="${APP_PROCESS_DEVICE_ID:-}"
APP_START_WAIT_SECONDS="${APP_START_WAIT_SECONDS:-5}"
RELATED_PROCESS_PATTERN="${RELATED_PROCESS_PATTERN:-$APP_PROCESS_NAME|xcodebuild|xctest|XCTest|UITests}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$CALLER_DIR/.derived-data}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-$CALLER_DIR/artifacts}"

ARTIFACT_BASENAME="${ARTIFACT_BASENAME:-UITestLeakRun}"
TRACE_PATH="${TRACE_PATH:-$ARTIFACTS_DIR/$ARTIFACT_BASENAME.trace}"
RECORDING_TRACE_PATH="${RECORDING_TRACE_PATH:-$ARTIFACTS_DIR/$ARTIFACT_BASENAME.in-progress.trace}"
TOC_XML="${TOC_XML:-$ARTIFACTS_DIR/$ARTIFACT_BASENAME-toc.xml}"
LEAKS_XML="${LEAKS_XML:-$ARTIFACTS_DIR/$ARTIFACT_BASENAME-leaks.xml}"
RECORD_LOG="${RECORD_LOG:-$ARTIFACTS_DIR/$ARTIFACT_BASENAME-xctrace-record.log}"
BUILD_LOG="${BUILD_LOG:-$ARTIFACTS_DIR/$ARTIFACT_BASENAME-build.log}"
TEST_LOG="${TEST_LOG:-$ARTIFACTS_DIR/$ARTIFACT_BASENAME-xcodebuild.log}"
DEVICE_INFO_LOG="${DEVICE_INFO_LOG:-$ARTIFACTS_DIR/$ARTIFACT_BASENAME-device-info.log}"

PARALLEL_TESTING_ENABLED="${PARALLEL_TESTING_ENABLED:-NO}"
DEFAULT_XCTRACE_TEMPLATE="$LEAK_DETECTOR_DIR/JustLeaks.tracetemplate"
if [[ ! -f "$DEFAULT_XCTRACE_TEMPLATE" ]]; then
  DEFAULT_XCTRACE_TEMPLATE="Leaks"
fi
XCTRACE_TEMPLATE="${XCTRACE_TEMPLATE:-$DEFAULT_XCTRACE_TEMPLATE}"
XCTRACE_DEVICE="${XCTRACE_DEVICE:-}"
XCTRACE_NO_PROMPT="${XCTRACE_NO_PROMPT:-1}"
XCTRACE_NOTIFY_NAME="${XCTRACE_NOTIFY_NAME:-com.example.xctrace.ui-test.started.$$}"
LEAKS_EXPORT_XPATH="${LEAKS_EXPORT_XPATH:-/trace-toc/run[@number=\"1\"]/tracks/track[@name=\"Leaks\"]/details/detail[@name=\"Leaks\"]}"
RUN_LEAK_CHECK="${RUN_LEAK_CHECK:-1}"
LEAK_CHECK_SCRIPT="${LEAK_CHECK_SCRIPT:-$LEAK_DETECTOR_DIR/check_xctrace_leaks.py}"
RECORD_START_WAIT_SECONDS="${RECORD_START_WAIT_SECONDS:-30}"
RECORD_WATCHDOG_SECONDS="${RECORD_WATCHDOG_SECONDS:-120}"
TOTAL_PHASES=6

print_phase() {
  local number="$1"
  local title="$2"

  if [[ "$number" -gt 1 ]]; then
    echo
  fi
  echo "[$number/$TOTAL_PHASES] $title"
  echo
}

if [[ -n "$PROJECT_PATH" && -n "$WORKSPACE_PATH" ]]; then
  echo "Set either PROJECT_PATH or WORKSPACE_PATH, not both." >&2
  exit 2
fi

if [[ -z "$PROJECT_PATH" && -z "$WORKSPACE_PATH" ]]; then
  echo "Set PROJECT_PATH or WORKSPACE_PATH." >&2
  exit 2
fi

for required_variable in SCHEME APP_PROCESS_NAME; do
  if [[ -z "${!required_variable}" ]]; then
    echo "Set $required_variable." >&2
    exit 2
  fi
done

mkdir -p "$ARTIFACTS_DIR"
rm -rf "$TRACE_PATH" "$RECORDING_TRACE_PATH" "$TOC_XML" "$LEAKS_XML"
rm -f "$RECORD_LOG" "$BUILD_LOG" "$TEST_LOG" "$DEVICE_INFO_LOG"

TEST_PID=""
APP_PID=""
RECORD_PID=""
NOTIFY_PID=""

XCODEBUILD_CONTAINER_ARGS=()
if [[ -n "$WORKSPACE_PATH" ]]; then
  XCODEBUILD_CONTAINER_ARGS=(-workspace "$WORKSPACE_PATH")
else
  XCODEBUILD_CONTAINER_ARGS=(-project "$PROJECT_PATH")
fi

TEST_FILTER_ARGS=()
if [[ -n "$TEST_IDENTIFIER" ]]; then
  TEST_FILTER_ARGS=(-only-testing:"$TEST_IDENTIFIER")
fi

cleanup() {
  if [[ -n "$NOTIFY_PID" ]] && kill -0 "$NOTIFY_PID" >/dev/null 2>&1; then
    kill "$NOTIFY_PID" >/dev/null 2>&1 || true
    wait "$NOTIFY_PID" >/dev/null 2>&1 || true
  fi

  if [[ -n "$TEST_PID" ]] && kill -0 "$TEST_PID" >/dev/null 2>&1; then
    kill "$TEST_PID" >/dev/null 2>&1 || true
    wait "$TEST_PID" >/dev/null 2>&1 || true
  fi

  if [[ -n "$RECORD_PID" ]] && kill -0 "$RECORD_PID" >/dev/null 2>&1; then
    kill "$RECORD_PID" >/dev/null 2>&1 || true
    wait "$RECORD_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

wait_for_app_pid() {
  local deadline=$((SECONDS + APP_START_WAIT_SECONDS))
  local process_list_json

  while [[ "$SECONDS" -lt "$deadline" ]]; do
    if [[ -n "$APP_PROCESS_DEVICE_ID" ]]; then
      process_list_json="$(mktemp /tmp/memory-leak-device-processes.XXXXXX)"
      if xcrun devicectl device info processes \
        --device "$APP_PROCESS_DEVICE_ID" \
        --json-output "$process_list_json" \
        --quiet \
        --timeout 5 \
        >/dev/null 2>&1; then
        APP_PID="$(python3 - "$process_list_json" "$APP_PROCESS_NAME" <<'PY'
import json
import sys
from urllib.parse import urlparse

with open(sys.argv[1], encoding="utf-8") as process_file:
    processes = json.load(process_file)["result"]["runningProcesses"]

matches = [
    process["processIdentifier"]
    for process in processes
    if urlparse(process.get("executable", "")).path.rsplit("/", 1)[-1] == sys.argv[2]
]

if matches:
    print(matches[-1])
PY
)"
      fi
      rm -f "$process_list_json"
    else
      APP_PID="$(pgrep -nx "$APP_PROCESS_NAME" || true)"
    fi

    if [[ -n "$APP_PID" ]]; then
      return 0
    fi

    if ! kill -0 "$TEST_PID" >/dev/null 2>&1; then
      return 1
    fi

    sleep 0.25
  done

  return 1
}

wait_for_recording_start() {
  local deadline=$((SECONDS + RECORD_START_WAIT_SECONDS))

  while [[ "$SECONDS" -lt "$deadline" ]]; do
    if [[ -n "$NOTIFY_PID" ]] && ! kill -0 "$NOTIFY_PID" >/dev/null 2>&1; then
      wait "$NOTIFY_PID" >/dev/null 2>&1 || true
      NOTIFY_PID=""
      echo "xctrace start notification observed: $XCTRACE_NOTIFY_NAME" >>"$RECORD_LOG"
      return 0
    fi

    if grep -Eq "Ctrl-C to stop the recording|Starting recording" "$RECORD_LOG" 2>/dev/null; then
      return 0
    fi

    if ! kill -0 "$RECORD_PID" >/dev/null 2>&1; then
      return 1
    fi

    sleep 0.5
  done

  return 1
}

wait_for_recorder_exit() {
  local status=0

  for _ in $(seq 0 "$RECORD_WATCHDOG_SECONDS"); do
    if ! kill -0 "$RECORD_PID" >/dev/null 2>&1; then
      if wait "$RECORD_PID"; then
        status=0
      else
        status=$?
      fi
      RECORD_PID=""
      return "$status"
    fi

    sleep 1
  done

  echo "xctrace did not finish after target exit timeout; terminating recorder." | tee -a "$RECORD_LOG"
  kill "$RECORD_PID" >/dev/null 2>&1 || true
  wait "$RECORD_PID" >/dev/null 2>&1 || true
  RECORD_PID=""
  return 124
}

print_phase 1 "Building UI test bundle..."
if ! xcodebuild \
  "${XCODEBUILD_CONTAINER_ARGS[@]}" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build-for-testing \
  >"$BUILD_LOG" 2>&1; then
  echo "UI test build failed. Details are in the artifacts directory." >&2
  exit 1
fi
echo "UI test bundle built."

pkill -x "$APP_PROCESS_NAME" >/dev/null 2>&1 || true

print_phase 2 "Starting UI test flow..."
xcodebuild \
  "${XCODEBUILD_CONTAINER_ARGS[@]}" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -parallel-testing-enabled "$PARALLEL_TESTING_ENABLED" \
  "${TEST_FILTER_ARGS[@]}" \
  test-without-building \
  >"$TEST_LOG" 2>&1 &
TEST_PID=$!

if ! wait_for_app_pid; then
  echo "Could not find the app process while the UI test was starting." >&2
  echo "Details are in the artifacts directory." >&2
  exit 1
fi

{
  echo "Host:"
  sw_vers
  echo
  echo "UI test xcodebuild process:"
  ps -p "$TEST_PID" -o pid= -o ppid= -o stat= -o command=
  echo
  echo "App process selected for recording:"
  if [[ -n "$APP_PROCESS_DEVICE_ID" ]]; then
    echo "  device=$APP_PROCESS_DEVICE_ID pid=$APP_PID executable=$APP_PROCESS_NAME"
  else
    ps -p "$APP_PID" -o pid= -o ppid= -o stat= -o command=
  fi
  echo
  echo "Recording configuration:"
  echo "  PROJECT_PATH=$PROJECT_PATH"
  echo "  WORKSPACE_PATH=$WORKSPACE_PATH"
  echo "  SCHEME=$SCHEME"
  echo "  DESTINATION=$DESTINATION"
  echo "  TEST_IDENTIFIER=$TEST_IDENTIFIER"
  echo "  APP_PROCESS_NAME=$APP_PROCESS_NAME"
  echo "  APP_PROCESS_DEVICE_ID=$APP_PROCESS_DEVICE_ID"
  echo "  APP_START_WAIT_SECONDS=$APP_START_WAIT_SECONDS"
  echo "  RELATED_PROCESS_PATTERN=$RELATED_PROCESS_PATTERN"
  echo "  PARALLEL_TESTING_ENABLED=$PARALLEL_TESTING_ENABLED"
  echo "  XCTRACE_TEMPLATE=$XCTRACE_TEMPLATE"
  echo "  XCTRACE_DEVICE=$XCTRACE_DEVICE"
  echo "  LEAKS_EXPORT_XPATH=$LEAKS_EXPORT_XPATH"
  echo "  RUN_LEAK_CHECK=$RUN_LEAK_CHECK"
  echo "  LEAK_CHECK_SCRIPT=$LEAK_CHECK_SCRIPT"
} >"$DEVICE_INFO_LOG"

print_phase 3 "Recording leaks with xctrace..."

if command -v notifyutil >/dev/null 2>&1; then
  notifyutil -1 "$XCTRACE_NOTIFY_NAME" >"$ARTIFACTS_DIR/macos-ui-test-xctrace-notify.log" 2>&1 &
  NOTIFY_PID=$!
fi

set -- xcrun xctrace record \
  --template "$XCTRACE_TEMPLATE" \
  --attach "$APP_PID" \
  --output "$RECORDING_TRACE_PATH" \
  --notify-tracing-started "$XCTRACE_NOTIFY_NAME"

if [[ -n "$XCTRACE_DEVICE" ]]; then
  set -- "$@" --device "$XCTRACE_DEVICE"
fi

if [[ "$XCTRACE_NO_PROMPT" -eq 1 ]]; then
  set -- "$@" --no-prompt
fi

{
  printf 'xctrace command:'
  printf ' %q' "$@"
  printf '\n'
  printf 'xctrace log: %s\n' "$RECORD_LOG"
} >"$RECORD_LOG"

"$@" >>"$RECORD_LOG" 2>&1 &
RECORD_PID=$!

if ! wait_for_recording_start; then
  echo "xctrace did not appear to start recording." >&2
  echo "Details are in the artifacts directory." >&2
  exit 1
fi

echo "Recording started; waiting for UI test process to finish..."

if wait "$TEST_PID"; then
  TEST_STATUS=0
else
  TEST_STATUS=$?
fi
TEST_PID=""

if wait_for_recorder_exit; then
  RECORD_STATUS=0
else
  RECORD_STATUS=$?
fi

echo "UI test exited with status $TEST_STATUS; xctrace exited with status $RECORD_STATUS."

if [[ "$TEST_STATUS" -ne 0 ]]; then
  echo "UI test failed. Details are in the artifacts directory." >&2
  exit "$TEST_STATUS"
fi

if [[ "$RECORD_STATUS" -ne 0 ]]; then
  if [[ -e "$RECORDING_TRACE_PATH" ]]; then
    echo "xctrace exited with status $RECORD_STATUS, but a trace was saved. Continuing to validate the trace."
  else
    echo "xctrace failed and did not produce a trace." >&2
    echo "Details are in the artifacts directory." >&2
    exit "$RECORD_STATUS"
  fi
fi

print_phase 4 "Validating trace..."
if ! xcrun xctrace export \
  --input "$RECORDING_TRACE_PATH" \
  --toc \
  --output "$TOC_XML" \
  >>"$RECORD_LOG" 2>&1; then
  echo "Trace validation failed. Details are in the artifacts directory." >&2
  exit 1
fi

rm -rf "$TRACE_PATH"
mv "$RECORDING_TRACE_PATH" "$TRACE_PATH"

print_phase 5 "Exporting Leaks details..."
if ! xcrun xctrace export \
  --input "$TRACE_PATH" \
  --output "$LEAKS_XML" \
  --xpath "$LEAKS_EXPORT_XPATH" \
  >>"$RECORD_LOG" 2>&1; then
  echo "Leaks export failed. Details are in the artifacts directory." >&2
  exit 1
fi

print_phase 6 "Checking exported leaks..."
if [[ "$RUN_LEAK_CHECK" -eq 1 ]]; then
  python3 "$LEAK_CHECK_SCRIPT" "$LEAKS_XML"
else
  echo "Skipping leak check."
fi
