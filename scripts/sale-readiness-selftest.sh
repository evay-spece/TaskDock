#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$PROJECT_ROOT"
source scripts/license-resources.sh
TEST_APP="$WORK/LicenseTest.app"
mkdir -p "$TEST_APP/Contents/MacOS"
taskdock_copy_license_resources "$PROJECT_ROOT" "$TEST_APP"
swiftc Sources/TaskDock/BetaCode.swift Sources/TaskDock/LicenseService.swift Sources/TaskDock/OfflineLicenseVerifier.swift \
  Sources/TaskDock/TaskDockLicenseResources.swift Sources/TaskDock/SystemDockVisibilityController.swift \
  scripts/offline-license-selftest.swift -o "$TEST_APP/Contents/MacOS/LicenseTest"
cp Resources/TaskDockBetaPublicKey.pem "$TEST_APP/Contents/Resources/TaskDockBetaPublicKey.pem"
printf 'ABCDEFGHJKLM' | shasum -a 256 | awk '{print $1}' > "$TEST_APP/Contents/Resources/TaskDockBetaCodeHashes.txt"
"$TEST_APP/Contents/MacOS/LicenseTest"
swiftc Sources/TaskDock/SystemDockVisibilityController.swift \
  scripts/system-dock-visibility-selftest.swift -o "$WORK/dock-selftest"
"$WORK/dock-selftest"

# A stale or damaged bundled resource must prevent successful verification.
echo damaged >> "$TEST_APP/Contents/Resources/license-public-key.pem"
if taskdock_verify_license_resources "$PROJECT_ROOT" "$TEST_APP" > "$WORK/resource-error.log" 2>&1; then
  echo 'Resource corruption was not detected' >&2; exit 1
fi
echo 'LICENSE_RESOURCES_OK copies-match corruption-rejected'
