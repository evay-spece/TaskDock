# Collapsed group controls — local 1.10.3 Build 173

- Shared rows in taskbar/fusion window bubbles: blue accent hover fill and white
  text, with a separate close-window button on the right. Selection still switches
  windows; closing does not intentionally dismiss the list.
- Actual-pointer tracking prevents stale hover highlights in nonactivating panels.
- Slightly increased count badge text/background contrast; dimensions unchanged.
- Collapsed groups expose the regular right-click actions, with the last action
  changed to 关闭该窗口组. Closing uses a group snapshot and refreshes once.
- Standard window closing presses AXCloseButton first, falling back to AXClose;
  Finder tab handling and native unsaved-changes prompts remain in place.

Validation: release build and strict signature verification; installed Build 173.
Observed blue/white row selection, the row close buttons, and the group context
menu including 关闭该窗口组. Actual single/group close outcomes remain unverified:
CUA repeatedly reported user-activity guards or invalidated elements during
execution. Temporary fixture windows/process and its recent-history entry were
cleaned up. Taskbar height 54 and inset 86 retained. No GitHub publication.
