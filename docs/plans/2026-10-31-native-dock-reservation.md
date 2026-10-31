# Native Dock reservation experiment Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Test whether the native Dock can reserve the TaskDock strip without AX lifting.
**Architecture:** An opt-in developer switch extends the existing Dock preference lifecycle. Back up only controlled Dock keys, show a bottom Dock under TaskDock with matching reserved height, disable magnification/bounces, calibrate against NSScreen.visibleFrame. Restore originals when disabled, native-Dock mode, access expiry, or quit. No public release or owner-default capture.
**Tech Stack:** Swift, AppKit, UserDefaults, SwiftUI, existing Accessibility fixtures.

1. Add lifecycle tests with isolated preference suites: hide→reserve→hide→restore; originally absent keys; crash/recreated controller; access denied; calibration/repeat limits; do not touch Dock favorites.
2. Extend SystemDockVisibilityController with reservation backups and bounded height calibration. Keep existing visibility selftests.
3. Add developer switch and measured-height status. Gate pointer avoidance while reservation is active, restoring only previously managed geometry when entering.
4. Build an isolated local candidate, SDK 27/minOS 12. Verify signature. Save the installed app to a recoverable backup before replacement.
5. On the primary Mac enable via UI; observe visibleFrame reservation and native maximize/half-screen using disposable windows. Inspect icon bleed and duplicate labels. Restore if unusable or validation is blocked; leave an explicit user-accessible switch for continued trials.
6. Record observed versus unverified results. Keep this worktree separate from WorkBuddy's 1.11.0 release checkout.

## Observed result — primary Mac, local Build 175

- Legacy plus new isolated preference tests passed: DOCK_VISIBILITY_OK.
- Release build passed (50.82s), code signature verified, source isolated from WorkBuddy release checkout.
- Taskbar height 54; native reservation target 60 pt. Initial measured inset 64;
  bounded calibration converged to 60 pt on the primary 2048×1152 display.
- Native SwiftUI disposable probe via actual Window menu: zoomed frame
  (0,60,2048,1062); left half (0,60,1025,1062); right half
  (1024,60,1024,1062). All bottom edges respect the system inset; AX pointer
  avoidance was disabled throughout reserved mode.
- Developer toggle OFF restored orientation, tilesize, magnification, launchanim,
  no-bouncing and Dock persistent-apps hash. Enabled then quit: all seven controlled
  values, including original absence of autohide-delay, restored exactly; both
  snapshots removed. Disposable probe terminated and only its recent entry removed.
- Installed local app: /Applications/TaskDock.app, 1.11.0 Build 175. Original
  installed 1.10.3 Build 173 kept in dist/retired/TaskDock-before-native-dock-reservation.app.
- Leave experiment ON for user trial with developer tab accessible. Existing owner
  appearance parameters untouched. Not merged into the release checkout or published.
- Glass/icon bleed and native tooltip conflicts need user observation; app-window
  screenshots alone cannot fully establish desktop compositing. Native full-screen
  spaces and cross-display Dock movement are not validated. Secondary display had
  no reserved inset; TaskDock currently occupies the primary display only.
