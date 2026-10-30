# Taskbar overflow correction — local Build 170

Use the task lane viewport's GeometryReader width directly when building the
collapsed groups. Remove the asynchronous preference/state width round trip.
Keep favorites, recent apps and outer margins outside this measured viewport.
Only groups containing multiple windows are eligible for overflow collapse;
prefer unfocused groups, and expand again when the viewport has room.
Single-window apps stay independent; horizontal scrolling remains the fallback
when collapsing all eligible groups still cannot fit everything.

Validation:
- Item sizing/overflow self-test: focused priority, downloads, single-window
  exclusion even with a shorter app name, and zero available width.
- NSHostingView viewport test: favorites and trailing-control reservations;
  wide/narrow/repeated resizing with automatic collapse and expansion.
- Release build, signature verification, macOS 12 minimum and SDK 27 linkage.
- Installed local 1.10.3 Build 170. Temporarily used inset 500 / height 64 and
  five disposable fixture windows: Edge (3) and fixture (5) collapsed. The
  fixture's five choices appeared on click; selecting one closed the bubble.
  Restoring inset 86 / height 54 expanded the groups again. Test process exited;
  removed only its exact-path recent entry. No GitHub publication performed.
