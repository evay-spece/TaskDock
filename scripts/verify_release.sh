#!/bin/zsh
set -euo pipefail
REPOSITORY="${1:?repository required}"
TAG="${2:?tag required}"
EXPECTED_SHA="${3:?expected SHA-256 required}"
VERSION="${TAG#v}"
ASSET="TaskDock-$VERSION-macOS-arm64.zip"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
gh release view "$TAG" -R "$REPOSITORY" --json tagName,assets > "$WORK/release.json"
curl -fL --retry 3 --max-time 180 \
  "https://github.com/$REPOSITORY/releases/download/$TAG/$ASSET" -o "$WORK/$ASSET"
ACTUAL_SHA="$(shasum -a 256 "$WORK/$ASSET" | awk '{print $1}')"
[[ "$ACTUAL_SHA" == "$EXPECTED_SHA" ]] || { echo "SHA-256 mismatch: $ACTUAL_SHA" >&2; exit 1; }
unzip -tq "$WORK/$ASSET" >/dev/null
mkdir "$WORK/extracted"
ditto -x -k "$WORK/$ASSET" "$WORK/extracted"
APP="$WORK/extracted/TaskDock.app"
[[ -d "$APP" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")" == <-> ]]
file "$APP/Contents/MacOS/TaskDock" | grep -q 'arm64'
codesign --verify --deep --strict "$APP"
echo "PUBLIC_RELEASE_VERIFIED $REPOSITORY $TAG $ASSET $ACTUAL_SHA"
