# Settings Tabs and Dock Scaling Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Split TaskDock settings into four clear tabs and make Dock Companion mode follow persistent Dock size changes while scaling its task items.

**Architecture:** Replace the single scrolling settings page with a macOS `TabView` containing General, Taskbar, Dock Companion, and Matrix sections. Detect Dock hover magnification from AX child item sizes instead of outer-list height, use current Dock defaults as a fallback on newer macOS versions, and centralize companion sizing in a pure helper shared by panel geometry and SwiftUI content.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, Accessibility APIs, UserDefaults, Swift Package Manager.

---

### Task 1: Add deterministic Dock sizing helpers

**Files:**
- Create: `Sources/TaskDock/DockCompanionSizing.swift`
- Create: `scripts/dock-companion-sizing-selftest.swift`
- Modify: `Sources/TaskDock/DockGeometryService.swift`

1. Add baseline, panel, item, content, width, and spacing calculations.
2. Detect temporary Dock magnification from actual AX Dock item widths.
3. Prefer current Dock-default estimates over stale cache when AX geometry is unavailable.
4. Run the sizing self-test; expect `DOCK_COMPANION_SIZING_OK`.

### Task 2: Scale the full companion UI

**Files:**
- Modify: `Sources/TaskDock/TaskbarPanelController.swift`
- Modify: `Sources/TaskDock/TaskbarView.swift`

1. Use the sizing helper for companion panel width and height.
2. Scale task-item frame, radius, padding, icon, typography, focus indicator, and control button.
3. Keep Taskbar and Matrix mode dimensions unchanged.
4. Build the debug target; expect success.

### Task 3: Reorganize Settings into four tabs

**Files:**
- Modify: `Sources/TaskDock/SettingsView.swift`
- Modify: `Sources/TaskDock/SettingsWindowController.swift`

1. Add General, Taskbar, Dock Companion, and Matrix tabs.
2. Move global behavior, app/window filtering, and updates to General.
3. Move alignment and favorites to Taskbar; explain automatic scaling in Dock Companion; describe matrix behavior in Matrix.
4. Give every tab its own scrollable content, empty states, and accessible controls.

### Task 4: Verify and hand off

**Files:**
- Verify: `Sources/TaskDock/*`
- Verify: `AppBundle/TaskDock.app`

1. Run sizing and existing window-filter tests.
2. Run Debug and arm64 Release builds.
3. Relaunch the stable-path app, inspect the settings tabs, and verify process/signature.
4. Commit locally without publishing to GitHub.
