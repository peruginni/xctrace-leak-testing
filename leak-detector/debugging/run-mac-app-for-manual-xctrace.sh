#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/apps/MemoryLeakingApp_MacOS/MemoryLeakingApp_MacOS.xcodeproj}"

SCHEME="${SCHEME:-MemoryLeakingApp_MacOS}"
APP_PROCESS_NAME="${APP_PROCESS_NAME:-MemoryLeakingApp_MacOS}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.derived-data}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-$ROOT_DIR/artifacts}"
APP_PATH="${APP_PATH:-$DERIVED_DATA_PATH/Build/Products/Debug/MemoryLeakingApp_MacOS.app}"
DEFAULT_XCTRACE_TEMPLATE="$ROOT_DIR/JustLeaks.tracetemplate"
if [[ ! -f "$DEFAULT_XCTRACE_TEMPLATE" ]]; then
  DEFAULT_XCTRACE_TEMPLATE="Leaks"
fi
XCTRACE_TEMPLATE="${XCTRACE_TEMPLATE:-$DEFAULT_XCTRACE_TEMPLATE}"

mkdir -p "$ARTIFACTS_DIR"

echo "Building macOS app..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

pkill -x "$APP_PROCESS_NAME" >/dev/null 2>&1 || true

echo "Launching $APP_PATH..."
open "$APP_PATH"

APP_PID=""
for _ in $(seq 1 30); do
  APP_PID="$(pgrep -x "$APP_PROCESS_NAME" | tail -n 1 || true)"
  if [[ -n "$APP_PID" ]]; then
    break
  fi

  sleep 1
done

if [[ -z "$APP_PID" ]]; then
  echo "Could not find process named $APP_PROCESS_NAME"
  exit 1
fi

echo
echo "macOS app process:"
echo "  app pid: $APP_PID"
ps -p "$APP_PID" -o pid= -o ppid= -o stat= -o command=

echo
echo "Manual Leaks attach command:"
echo "xcrun xctrace record --template '$XCTRACE_TEMPLATE' --attach $APP_PID --output '$ARTIFACTS_DIR/manual-mac-app-leaks.trace' --time-limit 5s --no-prompt"

echo
echo "Manual Time Profiler attach command:"
echo "xcrun xctrace record --template 'Time Profiler' --attach $APP_PID --output '$ARTIFACTS_DIR/manual-mac-app-time.trace' --time-limit 5s --no-prompt"

echo
echo "The app is running. Open/close the leaking sheet manually if needed, then run xctrace in another terminal."
