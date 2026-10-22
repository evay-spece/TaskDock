#!/bin/zsh
# Bundle the Finder Sync extension and document templates before signing TaskDock.
taskdock_copy_finder_extension() {
  local project_root="$1" app_path="$2" identity="$3"
  local extension="$app_path/Contents/PlugIns/TaskDockFinder.appex"
  mkdir -p "$extension/Contents/MacOS" "$app_path/Contents/Resources" || return 1
  cp "$project_root/FinderExtension/Info.plist" "$extension/Contents/Info.plist" || return 1
  cp "$project_root/Resources/blank.xlsx" "$project_root/Resources/blank.docx" "$app_path/Contents/Resources/" || return 1
  xcrun swiftc -O -target arm64-apple-macos12.0 \
    -framework AppKit -framework FinderSync -framework Carbon \
    "$project_root/Sources/TaskDock/FileTypeSettings.swift" \
    "$project_root/Sources/TaskDock/FileCreator.swift" \
    "$project_root/Sources/TaskDock/ClipboardCutter.swift" \
    "$project_root/FinderExtension/FinderExtension.swift" \
    -Xlinker -e -Xlinker _NSExtensionMain \
    -o "$extension/Contents/MacOS/TaskDockFinder" || return 1
  codesign --force --sign "$identity" --timestamp=none \
    --entitlements "$project_root/FinderExtension/Finder.entitlements" "$extension" || return 1
  codesign --verify --strict "$extension" || return 1
}

taskdock_verify_finder_extension() {
  local project_root="$1" app_path="$2"
  local extension="$app_path/Contents/PlugIns/TaskDockFinder.appex"
  [[ -x "$extension/Contents/MacOS/TaskDockFinder" ]] || return 1
  codesign --verify --strict "$extension" || return 1
  cmp "$project_root/Resources/blank.xlsx" "$app_path/Contents/Resources/blank.xlsx" || return 1
  cmp "$project_root/Resources/blank.docx" "$app_path/Contents/Resources/blank.docx" || return 1
}
