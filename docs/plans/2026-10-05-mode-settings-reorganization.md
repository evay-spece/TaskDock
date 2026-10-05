# Mode Settings Reorganization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move appearance, inactive-item opacity, and window inclusion from General to mode-specific settings; standardize discrete choices as dropdowns.

**Architecture:** Keep existing legacy UserDefaults keys as migration inputs. Store per-mode values under new keys, expose mode-aware accessors to rendering and window enumeration, and leave the Fusion appearance on its existing automatic system match until explicitly changed. The settings view binds each mode's controls to its dedicated values.

**Tech Stack:** Swift, SwiftUI, AppKit, UserDefaults, Swift Package Manager.

---

### Task 1: Model and migration

**Files:** `Sources/TaskDock/SettingsStore.swift`

1. Add per-mode appearance, inactive opacity, hidden-app and Finder-tab values with defaults migrated from existing shared keys.
2. Preserve existing values and write the new keys without deleting old keys.
3. Add mode-aware accessors and verify a release build.

### Task 2: Runtime routing

**Files:** `Sources/TaskDock/TaskbarView.swift`, `Sources/TaskDock/TaskbarPanelController.swift`, `Sources/TaskDock/SettingsWindowController.swift`

1. Route current mode's appearance and opacity into rendering.
2. Route current mode's window inclusion values into enumeration.
3. Preserve Fusion's automatic appearance default.

### Task 3: Settings layout

**Files:** `Sources/TaskDock/SettingsView.swift`

1. Remove shared appearance, opacity, window-display and system-Dock sections from General.
2. Add applicable controls to each mode page, with experimental badges on Fusion and Matrix.
3. Convert discrete Pickers and finite-count Steppers to dropdown menus; retain true/false toggles and the continuous height slider.

### Task 4: Verification and local handoff

1. Run `swift build -c release`, related self-tests, and `git diff --check`.
2. Update and re-open the stable-path app, confirm signature, version and sole running process.
3. Inspect the actual settings window if the Mac is unlocked; otherwise report visual verification as open.
