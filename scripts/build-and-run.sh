#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$PROJECT_ROOT/AppBundle/TaskDock.app"
EXECUTABLE_PATH="$PROJECT_ROOT/.build/arm64-apple-macosx/debug/TaskDock"
ICON_SOURCE="$PROJECT_ROOT/Resources/TaskDockIcon.png"
DETECTED_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/Apple Development/ { print $2; exit }')"
SIGNING_IDENTITY="${TASKDOCK_SIGNING_IDENTITY:-${DETECTED_IDENTITY:--}}"

cd "$PROJECT_ROOT"
swift build
mkdir -p "$APP_PATH/Contents/MacOS"
cp "$EXECUTABLE_PATH" "$APP_PATH/Contents/MacOS/TaskDock"
if [[ -f "$ICON_SOURCE" ]]; then
  ICON_WORK_DIR="$(mktemp -d)"
  ICONSET_PATH="$ICON_WORK_DIR/TaskDock.iconset"
  mkdir -p "$ICONSET_PATH" "$APP_PATH/Contents/Resources"
  sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_512x512.png" >/dev/null
  cp "$ICON_SOURCE" "$ICONSET_PATH/icon_512x512@2x.png"
  iconutil -c icns "$ICONSET_PATH" -o "$APP_PATH/Contents/Resources/TaskDock.icns"
  rm -rf "$ICON_WORK_DIR"
fi
codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$APP_PATH"
xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true
killall -9 TaskDock 2>/dev/null || true
open -n "$APP_PATH"

echo "TaskDock 已更新并启动：$APP_PATH"
