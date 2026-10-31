# Standard-layout one-shot adjustment

Goal: retire native Dock reservation for this trial and replace pointer-triggered animated lifts with one bottom-edge size update after a standard full/half layout settles.

1. Add a pure geometry/state policy, with regressions for stable-frame waiting, manual/ordinary/off-screen exclusion, drag suppression, immediate app rebound, and a later distinct maximize/tile operation.
2. Call it only for focused standard, nonfullscreen, visible windows. Record the request before AX writes, do not retry an app rejection. Preserve top/left/width. Restore only still-owned adjusted geometry when exiting.
3. Replace old animation/pointer controls with a standard-layout toggle and settle delay. Native reservation stays disabled; no default snapshot recapture or publication.
4. Build/install local Build 177, verify native Dock settings restored, test full and half with the disposable probe, and confirm an ordinary overlapping window remains unchanged. Mark any manual-intent/third-party limitations honestly.

## Implementation and validation so far

- Installed local 1.11.0 Build 177; native reservation flag is false. Native Dock
  orientation/size/magnification/bounce overrides restored; ordinary TaskDock Dock
  hiding remains active. The developer page now has a standard-layout toggle and
  settle delay instead of the retired lift/native-reservation controls.
- STANDARD_LAYOUT_ONCE_OK covers full/half targets, ordinary/off-screen exclusion,
  frame settling, drag suppression, immediate rejection without retries, and a
  later distinct layout episode. Release compile and strict signature passed.
- Added a 0.5s AX client messaging timeout after profiling Build 176 stuck in
  AXUIElementCopyAttributeValue. Its unresponsive development process was stopped
  with SIGTERM after UI quit attempts timed out; preference snapshots were retained
  and recovered by Build 177.
- Ordinary blank probe started at Cocoa (674,0,700,500) with no reserved screen
  inset. It stayed unchanged. Automated zoom made it (0,0,2048,1122), but the probe
  remained a background app, so the foreground-only policy correctly did not act.
  Requested one human click to activate it before completing end-to-end validation.
- Image capture failed while the disk had ~206 MB free. Removed only regenerable
  SDK/module caches from this experiment worktree; the next check reported 5.4 GB
  available and image capture recovered. Source, app backups and user files retained.
