# The shelf is a titled, non-activating panel

Date: 2026-10-11

Status: accepted

## Context

The shelf opens over whatever app you are using, takes typing (search, arrow keys, Return) and then pastes into that app. So it must receive keyboard input while the other app stays the active app: if myClips becomes active, `⌘V` lands in myClips and the user's menu bar switches away.

The first version used a borderless `NSPanel` with `.nonactivatingPanel` and closed itself when it lost key status. Its keystrokes went to the app behind it, so nothing could be typed, and opening the screenshot tool closed it.

## Decision

- `NSPanel` with `[.nonactivatingPanel, .titled, .fullSizeContentView]`, title bar hidden and transparent, `canBecomeKey` overridden to `true`. With `.titled` the panel reliably becomes the key window without activating myClips.
- All shelf keys go through one local `keyDown` monitor in `PanelController`. The search field keeps focus; letters are matched by character so shortcuts follow the keyboard layout.
- The shelf closes on explicit events only — `Esc`, the hotkey, a paste, a mouse click outside it, or another app activating — never on losing key status. Clicks are ignored while the system screenshot UI (`screencaptureui`) is on screen.
- Before posting `⌘V`, the paster re-activates the app that was frontmost when the shelf opened if myClips somehow became active.

## Consequences

- Typing and pasting work without stealing the user's active app; verified end to end with the UI driver.
- Arrow keys move between cards, so they can't move the cursor inside the search field.
- The panel uses `.floating` level. A higher level (`.popUpMenu`) drew over its own context menus.
- One `FocusState` for the whole panel: separate focus states for the search field and the new-pinboard field fought over the first responder.
