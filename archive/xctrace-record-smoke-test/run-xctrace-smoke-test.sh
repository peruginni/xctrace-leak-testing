#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-$ROOT_DIR/artifacts}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
TEMPLATE="${TEMPLATE:-Time Profiler}"
TIME_LIMIT="${TIME_LIMIT:-5s}"
RECORD_WATCHDOG_SECONDS="${RECORD_WATCHDOG_SECONDS:-30}"
RECORD_STOP_GRACE_SECONDS="${RECORD_STOP_GRACE_SECONDS:-5}"
XCTRACE_NO_PROMPT="${XCTRACE_NO_PROMPT:-1}"
TRACE_BASENAME="${TRACE_BASENAME:-$(echo "$TEMPLATE" | tr '[:upper:] ' '[:lower:]-')}"

mkdir -p "$ARTIFACTS_DIR" "$BUILD_DIR"

TARGET="$BUILD_DIR/leaky_process"
TRACE_PATH="$ARTIFACTS_DIR/$TRACE_BASENAME.trace"
TOC_PATH="$ARTIFACTS_DIR/$TRACE_BASENAME-toc.xml"
RECORD_LOG="$ARTIFACTS_DIR/$TRACE_BASENAME-xctrace-record.log"
TARGET_LOG="$ARTIFACTS_DIR/$TRACE_BASENAME-target.log"
NOTIFY_LOG="$ARTIFACTS_DIR/$TRACE_BASENAME-notify.log"
NOTIFY_NAME="com.example.xctrace-smoke-test.started.$$"

rm -rf "$TRACE_PATH" "$TOC_PATH" "$RECORD_LOG" "$TARGET_LOG" "$NOTIFY_LOG"

echo "Compiling local target..."
clang -g -O0 "$ROOT_DIR/leaky_process.c" -o "$TARGET"

"$TARGET" >"$TARGET_LOG" 2>&1 &
TARGET_PID=$!
RECORD_PID=""
NOTIFY_PID=""

cleanup() {
  if [[ -n "$NOTIFY_PID" ]] && kill -0 "$NOTIFY_PID" >/dev/null 2>&1; then
    kill "$NOTIFY_PID" >/dev/null 2>&1 || true
    wait "$NOTIFY_PID" >/dev/null 2>&1 || true
  fi

  if [[ -n "$RECORD_PID" ]] && kill -0 "$RECORD_PID" >/dev/null 2>&1; then
    kill "$RECORD_PID" >/dev/null 2>&1 || true
    wait "$RECORD_PID" >/dev/null 2>&1 || true
  fi

  if kill -0 "$TARGET_PID" >/dev/null 2>&1; then
    kill "$TARGET_PID" >/dev/null 2>&1 || true
    wait "$TARGET_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

for _ in $(seq 1 20); do
  if grep -q "leaky_process pid=" "$TARGET_LOG"; then
    break
  fi

  if ! kill -0 "$TARGET_PID" >/dev/null 2>&1; then
    echo "Target exited before xctrace could attach:"
    cat "$TARGET_LOG" || true
    exit 1
  fi

  sleep 0.1
done

echo "Target:"
cat "$TARGET_LOG"

if command -v notifyutil >/dev/null 2>&1; then
  notifyutil -1 "$NOTIFY_NAME" >"$NOTIFY_LOG" 2>&1 &
  NOTIFY_PID=$!
fi

set -- xcrun xctrace record \
  --template "$TEMPLATE" \
  --attach "$TARGET_PID" \
  --output "$TRACE_PATH" \
  --time-limit "$TIME_LIMIT" \
  --notify-tracing-started "$NOTIFY_NAME"

if [[ "$XCTRACE_NO_PROMPT" -eq 1 ]]; then
  set -- "$@" --no-prompt
fi

{
  printf 'xctrace command:'
  printf ' %q' "$@"
  printf '\n'
} | tee "$RECORD_LOG"

"$@" >>"$RECORD_LOG" 2>&1 &
RECORD_PID=$!
RECORD_STATUS=""

for elapsed in $(seq 0 "$RECORD_WATCHDOG_SECONDS"); do
  if ! kill -0 "$RECORD_PID" >/dev/null 2>&1; then
    set +e
    wait "$RECORD_PID"
    RECORD_STATUS=$?
    set -e
    break
  fi

  if [[ "$elapsed" -eq "$RECORD_WATCHDOG_SECONDS" ]]; then
    {
      echo "xctrace did not finish within ${RECORD_WATCHDOG_SECONDS}s."
      echo "Sending SIGINT, then waiting ${RECORD_STOP_GRACE_SECONDS}s."
    } >>"$RECORD_LOG"

    kill -INT "$RECORD_PID" >/dev/null 2>&1 || true

    for _ in $(seq 1 "$RECORD_STOP_GRACE_SECONDS"); do
      if ! kill -0 "$RECORD_PID" >/dev/null 2>&1; then
        set +e
        wait "$RECORD_PID"
        RECORD_STATUS=$?
        set -e
        break
      fi

      sleep 1
    done

    if [[ -z "$RECORD_STATUS" ]]; then
      echo "xctrace did not stop after SIGINT; sending SIGTERM." >>"$RECORD_LOG"
      kill -TERM "$RECORD_PID" >/dev/null 2>&1 || true
      sleep 2
    fi

    if kill -0 "$RECORD_PID" >/dev/null 2>&1; then
      echo "xctrace did not stop after SIGTERM; sending SIGKILL." >>"$RECORD_LOG"
      kill -KILL "$RECORD_PID" >/dev/null 2>&1 || true
      sleep 1
    fi

    wait "$RECORD_PID" >/dev/null 2>&1 || true
    RECORD_STATUS=124
    break
  fi

  sleep 1
done

RECORD_PID=""

if [[ -n "$NOTIFY_PID" ]]; then
  if kill -0 "$NOTIFY_PID" >/dev/null 2>&1; then
    kill "$NOTIFY_PID" >/dev/null 2>&1 || true
    wait "$NOTIFY_PID" >/dev/null 2>&1 || true
    echo "xctrace did not send $NOTIFY_NAME" >>"$RECORD_LOG"
  else
    wait "$NOTIFY_PID" >/dev/null 2>&1 || true
    echo "xctrace sent $NOTIFY_NAME" >>"$RECORD_LOG"
  fi
  NOTIFY_PID=""
fi

echo "Recorder exit status: $RECORD_STATUS"
tail -n 40 "$RECORD_LOG" || true

if [[ "$RECORD_STATUS" -ne 0 ]]; then
  echo "xctrace record failed"
  exit "$RECORD_STATUS"
fi

echo "Validating trace with xctrace export --toc..."
xcrun xctrace export \
  --input "$TRACE_PATH" \
  --toc \
  --output "$TOC_PATH"

echo "Valid trace:"
echo "  trace: $TRACE_PATH"
echo "  toc:   $TOC_PATH"
