#!/bin/zsh
# Called before the outer app signature. No native host is registered during builds.
taskdock_copy_browser_bridge() {
  local project_root="$1" app_path="$2" binary_directory="$3"
  [[ -x "$binary_directory/TaskDockBrowserHost" ]] || { echo '缺少浏览器本机组件' >&2; return 1; }
  mkdir -p "$app_path/Contents/Helpers" "$app_path/Contents/Resources/BrowserExtension" || return 1
  cp "$binary_directory/TaskDockBrowserHost" "$app_path/Contents/Helpers/TaskDockBrowserHost" || return 1
  ditto "$project_root/BrowserExtension" "$app_path/Contents/Resources/BrowserExtension" || return 1
}
taskdock_sign_browser_bridge() {
  local app_path="$1" identity="$2"
  codesign --force --sign "$identity" --timestamp=none "$app_path/Contents/Helpers/TaskDockBrowserHost" || return 1
  codesign --verify --strict "$app_path/Contents/Helpers/TaskDockBrowserHost" || return 1
}
taskdock_verify_browser_bridge() {
  local project_root="$1" app_path="$2"
  [[ -x "$app_path/Contents/Helpers/TaskDockBrowserHost" ]] || return 1
  codesign --verify --strict "$app_path/Contents/Helpers/TaskDockBrowserHost" || return 1
  local resource
  for resource in manifest.json background.js progress.js popup.html popup.js popup.css 安装说明.txt; do
    cmp "$project_root/BrowserExtension/$resource" "$app_path/Contents/Resources/BrowserExtension/$resource" || return 1
  done
  for resource in 16 32 48 128; do
    cmp "$project_root/BrowserExtension/icons/icon$resource.png" "$app_path/Contents/Resources/BrowserExtension/icons/icon$resource.png" || return 1
  done
}
