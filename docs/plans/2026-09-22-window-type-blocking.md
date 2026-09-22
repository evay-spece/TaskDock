# Window Type Blocking Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let users hide a recurring unwanted window type from a TaskDock item menu and restore it later in Settings.

**Architecture:** Persist stable rules composed from the owning app, raw accessibility title, role, and subrole. Apply the rules while enumerating accessibility windows, before a `WindowModel` reaches the UI. Expose rule creation in both right-click and long-press menus, and expose rule removal in Settings.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit accessibility APIs, UserDefaults, Swift Package Manager.

---

### Task 1: Add the persistent rule model

**Files:**
- Modify: `Sources/TaskDock/Models.swift`
- Modify: `Sources/TaskDock/SettingsStore.swift`
- Test: `scripts/window-rule-selftest.swift`

1. Add a Codable, Hashable `BlockedWindowRule` with a deterministic identifier and a matching method.
2. Add the raw accessibility title, role, and subrole to `WindowModel`.
3. Persist deduplicated rules in UserDefaults and provide add/remove methods.
4. Compile and run the self-test; expect `WINDOW_RULE_OK`.

### Task 2: Apply rules during accessibility enumeration

**Files:**
- Modify: `Sources/TaskDock/AXWindowService.swift`
- Modify: `Sources/TaskDock/TaskbarPanelController.swift`

1. Pass blocked rules into every window enumeration.
2. Reject matching windows before creating `WindowModel` values.
3. Keep the “minimize all” action independent of user display filters.
4. Build the debug target; expect success.

### Task 3: Add user controls

**Files:**
- Modify: `Sources/TaskDock/TaskbarView.swift`
- Modify: `Sources/TaskDock/SettingsView.swift`
- Modify: `Sources/TaskDock/SettingsWindowController.swift`

1. Add “屏蔽此类窗口” to right-click and long-press menus.
2. Apply the rule immediately and refresh TaskDock.
3. Add an “已屏蔽的窗口类型” section in Settings with app, window label, and a restore button.
4. Provide an empty state and accessibility labels.

### Task 4: Verify and hand off

**Files:**
- Verify: `Sources/TaskDock/*`
- Verify: `AppBundle/TaskDock.app`

1. Run rule tests, existing filter tests, Debug build, and arm64 Release build.
2. Relaunch the stable-path app and verify its process and signature.
3. Commit the feature without publishing it to GitHub.
