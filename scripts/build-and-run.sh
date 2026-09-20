#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$PROJECT_ROOT/AppBundle/TaskDock.app"
EXECUTABLE_PATH="$PROJECT_ROOT/.build/arm64-apple-macosx/debug/TaskDock"
DETECTED_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/Apple Development/ { print $2; exit }')"
SIGNING_IDENTITY="${TASKDOCK_SIGNING_IDENTITY:-${DETECTED_IDENTITY:--}}"

cd "$PROJECT_ROOT"
swift build
mkdir -p "$APP_PATH/Contents/MacOS"
cp "$EXECUTABLE_PATH" "$APP_PATH/Contents/MacOS/TaskDock"
codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$APP_PATH"
killall -9 TaskDock 2>/dev/null || true
open -n "$APP_PATH"

echo "TaskDock 已更新并启动：$APP_PATH"
