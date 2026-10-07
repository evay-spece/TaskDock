#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT/AppBundle/TaskDock.app/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PROJECT_ROOT/AppBundle/TaskDock.app/Contents/Info.plist")"
ASSET="$PROJECT_ROOT/dist/TaskDock-$VERSION-macOS-arm64.zip"
[[ "$BUILD" == <-> ]] || { echo "Build number must be an integer" >&2; exit 1; }
[[ ! -e "$ASSET" ]] || { echo "Refusing to replace existing asset: $ASSET" >&2; exit 1; }

SDK="${TASKDOCK_BUILD_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
SWIFT_ARGS=(-c release --arch arm64)
[[ -d "$SDK" ]] && SWIFT_ARGS+=(--sdk "$SDK")
cd "$PROJECT_ROOT"
swift build "${SWIFT_ARGS[@]}"
BIN="$(swift build "${SWIFT_ARGS[@]}" --show-bin-path)/TaskDock"
[[ -f "$BIN" ]] || { echo "Missing release executable: $BIN" >&2; exit 1; }
file "$BIN" | grep -q 'arm64' || { echo "Release executable is not arm64" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/TaskDock.app"
ditto "$PROJECT_ROOT/AppBundle/TaskDock.app" "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TaskDock"
ICON_SOURCE="$PROJECT_ROOT/Resources/TaskDockIcon.png"
if [[ -f "$ICON_SOURCE" ]]; then
  ICONSET="$WORK/TaskDock.iconset"
  mkdir -p "$ICONSET"
  for spec in '16 16 icon_16x16' '32 32 icon_16x16@2x' \
              '32 32 icon_32x32' '64 64 icon_32x32@2x' \
              '128 128 icon_128x128' '256 256 icon_128x128@2x' \
              '256 256 icon_256x256' '512 512 icon_256x256@2x' \
              '512 512 icon_512x512'; do
    parts=(${=spec})
    sips -z "$parts[1]" "$parts[2]" "$ICON_SOURCE" --out "$ICONSET/$parts[3].png" >/dev/null
  done
  cp "$ICON_SOURCE" "$ICONSET/icon_512x512@2x.png"
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/TaskDock.icns"
fi

IDENTITY="${TASKDOCK_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/Apple Development/ { print $2; exit }')}"
[[ -n "$IDENTITY" ]] || IDENTITY='-'
codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")" == "$BUILD" ]]

mkdir -p "$PROJECT_ROOT/dist"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ASSET"
unzip -tq "$ASSET" >/dev/null
mkdir "$WORK/extracted"
ditto -x -k "$ASSET" "$WORK/extracted"
EXTRACTED="$WORK/extracted/TaskDock.app"
codesign --verify --deep --strict "$EXTRACTED"
file "$EXTRACTED/Contents/MacOS/TaskDock" | grep -q 'arm64'
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$EXTRACTED/Contents/Info.plist")" == "$VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$EXTRACTED/Contents/Info.plist")" == "$BUILD" ]]
echo "ASSET=$ASSET"
echo "VERSION=$VERSION BUILD=$BUILD"
shasum -a 256 "$ASSET"
