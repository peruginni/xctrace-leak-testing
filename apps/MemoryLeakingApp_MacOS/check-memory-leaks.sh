#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEAK_DETECTOR_DIR="$APP_DIR/../../leak-detector"

export CALLER_DIR="$APP_DIR"
export PROJECT_PATH="$APP_DIR/MemoryLeakingApp_MacOS.xcodeproj"
export SCHEME="MemoryLeakingApp_MacOS"
export DESTINATION="platform=macOS"
export TEST_IDENTIFIER="MemoryLeakingApp_MacOSUITests/MemoryLeakingApp_MacOSUITests/testOpenAndCloseLeakingScreenRepeatedly"
export APP_PROCESS_NAME="MemoryLeakingApp_MacOS"
export ARTIFACT_BASENAME="MacUITestLeakRun"

exec "$LEAK_DETECTOR_DIR/run-ui-test-leak-workflow.sh"
