#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT/AppBundle/TaskDock.app/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PROJECT_ROOT/AppBundle/TaskDock.app/Contents/Info.plist")"
OUTPUT_DIRECTORY="${TASKDOCK_OUTPUT_DIRECTORY:-$PROJECT_ROOT/dist}"
ASSET="$OUTPUT_DIRECTORY/TaskDock-$VERSION-macOS-arm64.zip"
[[ "$BUILD" == <-> ]] || { echo "Build number must be an integer" >&2; exit 1; }
[[ ! -e "$ASSET" ]] || { echo "Refusing to replace existing asset: $ASSET" >&2; exit 1; }
python3 "$PROJECT_ROOT/scripts/capture-release-appearance.py" --check

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
SDK="${TASKDOCK_BUILD_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
SWIFT_ARGS=(-c release --arch arm64)
if [[ -n "$SDK" ]]; then
  [[ -d "$SDK" ]] || { echo "SDK does not exist: $SDK" >&2; exit 1; }
  SWIFT_ARGS+=(--sdk "$SDK")
fi
# Record the actual SDK so system controls adopt its current design, while
# retaining the package's macOS 12 deployment target.
SDK_VERSION="$(xcrun --sdk "$SDK" --show-sdk-version)"
SWIFT_ARGS+=(-Xlinker -platform_version -Xlinker macos -Xlinker 12.0 -Xlinker "$SDK_VERSION")
cd "$PROJECT_ROOT"
swift build "${SWIFT_ARGS[@]}"
BIN="$(swift build "${SWIFT_ARGS[@]}" --show-bin-path)/TaskDock"
[[ -f "$BIN" ]] || { echo "Missing release executable: $BIN" >&2; exit 1; }
file "$BIN" | grep -q 'arm64' || { echo "Release executable is not arm64" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/TaskDock.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$PROJECT_ROOT/AppBundle/TaskDock.app/Contents/Info.plist" "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/TaskDock"
source "$PROJECT_ROOT/scripts/browser-bridge-resources.sh"
taskdock_copy_browser_bridge "$PROJECT_ROOT" "$APP" "$(dirname "$BIN")"
source "$PROJECT_ROOT/scripts/license-resources.sh"
taskdock_copy_license_resources "$PROJECT_ROOT" "$APP"
BETA_PUBLIC_KEY="$PROJECT_ROOT/Resources/TaskDockBetaPublicKey.pem"
[[ -f "$BETA_PUBLIC_KEY" ]] || { echo "Missing beta activation public key" >&2; exit 1; }
cp "$BETA_PUBLIC_KEY" "$APP/Contents/Resources/TaskDockBetaPublicKey.pem"
BETA_CODE_HASHES="$PROJECT_ROOT/Resources/TaskDockBetaCodeHashes.txt"
[[ -f "$BETA_CODE_HASHES" ]] || { echo "Missing beta code hash pool" >&2; exit 1; }
cp "$BETA_CODE_HASHES" "$APP/Contents/Resources/TaskDockBetaCodeHashes.txt"
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
taskdock_sign_browser_bridge "$APP" "$IDENTITY"
source "$PROJECT_ROOT/scripts/finder-extension-resources.sh"
taskdock_copy_finder_extension "$PROJECT_ROOT" "$APP" "$IDENTITY"
codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")" == "$BUILD" ]]

mkdir -p "$OUTPUT_DIRECTORY"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ASSET"
unzip -tq "$ASSET" >/dev/null
mkdir "$WORK/extracted"
ditto -x -k "$ASSET" "$WORK/extracted"
EXTRACTED="$WORK/extracted/TaskDock.app"
codesign --verify --deep --strict "$EXTRACTED"
cmp "$BETA_PUBLIC_KEY" "$EXTRACTED/Contents/Resources/TaskDockBetaPublicKey.pem"
cmp "$BETA_CODE_HASHES" "$EXTRACTED/Contents/Resources/TaskDockBetaCodeHashes.txt"
taskdock_verify_license_resources "$PROJECT_ROOT" "$EXTRACTED"
taskdock_verify_browser_bridge "$PROJECT_ROOT" "$EXTRACTED"
taskdock_verify_finder_extension "$PROJECT_ROOT" "$EXTRACTED"
file "$EXTRACTED/Contents/MacOS/TaskDock" | grep -q 'arm64'
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$EXTRACTED/Contents/Info.plist")" == "$VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$EXTRACTED/Contents/Info.plist")" == "$BUILD" ]]
echo "ASSET=$ASSET"
echo "VERSION=$VERSION BUILD=$BUILD"
shasum -a 256 "$ASSET"
