# Favorite Hover and Reorder Animation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Keep the rightmost favorite enlarged until the pointer leaves its full visual safety area, and visibly animate favorite icons when drag-reordering changes their positions.

**Architecture:** Use the existing `FavoriteMagnificationLayout.sideClearance` as the hover tracking margin. In `FavoriteDockVisualView.DrawingView`, retain icon and indicator layers by favorite ID across order changes, then animate only layers whose target position changes; keep the dragged icon attached to the pointer and animate its final settling motion.

**Tech Stack:** SwiftUI, AppKit tracking areas, Core Animation, Swift self-test, macOS app bundle.

---

### Task 1: Right-edge hover safety

**Files:** `Sources/TaskDock/TaskbarView.swift`, `Sources/TaskDock/FavoriteMagnificationLayout.swift`, `scripts/favorite-magnification-selftest.swift`

1. Make hover tracking use the same side clearance as the magnified icon geometry.
2. Add a self-test that verifies the safety margin covers the outermost enlarged icon across supported taskbar scales.
3. Run `swiftc Sources/TaskDock/FavoriteMagnificationLayout.swift scripts/favorite-magnification-selftest.swift -o /tmp/taskdock-favorite-magnification-selftest && /tmp/taskdock-favorite-magnification-selftest`; expect `FAVORITE_MAGNIFICATION_OK`.

### Task 2: Animated favorite reordering

**Files:** `Sources/TaskDock/TaskbarView.swift`

1. Preserve CALayers by favorite ID when the favorite order changes; create or remove layers only for actual additions/removals.
2. Animate affected stationary icons and their running indicators into shifted slots. Keep the dragged icon immediate under the pointer and animate it into its final slot on release.
3. Build the release target using the macOS 26.5 SDK, then restart the stable local app and inspect the taskbar visually. Test a reversible favorite reorder and restore the original order.

### Task 3: Final checks

**Files:** `Sources/TaskDock/TaskbarView.swift`, `scripts/favorite-magnification-selftest.swift`

1. Run `git diff --check`, the magnification self-test, release build, app signature validation, and exact process-path check.
2. Report the hover and drag observations separately. Do not publish a GitHub Release without an explicit request.
