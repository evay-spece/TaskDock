#!/bin/zsh
set -euo pipefail
[[ "${1:-}" == '--confirmed' ]] || { echo 'Pass --confirmed after exact-version publication authorization' >&2; exit 1; }
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT/AppBundle/TaskDock.app/Contents/Info.plist")"
TAG="v$VERSION"
ASSET="$PROJECT_ROOT/dist/TaskDock-$VERSION-macOS-arm64.zip"
NOTES="$PROJECT_ROOT/docs/releases/$VERSION.md"
[[ -f "$ASSET" && -f "$NOTES" ]]
git -C "$PROJECT_ROOT" ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null
if gh release view "$TAG" -R evay-spece/TaskDock >/dev/null 2>&1; then
  echo "Release already exists: $TAG" >&2
  exit 1
fi
gh release create "$TAG" "$ASSET" -R evay-spece/TaskDock \
  --title "TaskDock $TAG" --notes-file "$NOTES" --verify-tag
