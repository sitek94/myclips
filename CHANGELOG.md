# Changelog

## 0.5.0 — 2026-10-18

- The shelf sits on the bottom edge of the screen: full width, 8 pt in, over the Dock; it slides up and back down.
- The main list is called Clipboard (it was History), also in Settings and the menu (Clear Clipboard…).
- New cards: a header in the source app's color (taken from its icon) says what the clip is (Text, Link, Image, File, Color) and how old it is, with the app's icon large in its corner. Text cards show about nine lines; the size and ⌘1–⌘9 sit at the bottom. The ⏎ Paste button on the selected card is gone; Return still pastes.
- Drag a card, or the whole selection as a stack, into any app; the shelf slides away when the pointer leaves it.
- Sounds: one when a clip is saved, one when you paste. Pick each in Settings, also from your own `~/Library/Sounds`, or turn them off.

## 0.4.0 — 2026-10-15

- A new look, shared with myCapture: the shelf is a glass strip 40 pt from the screen edges that slides in and out. Each card shows the clip in a rounded box with the source app's icon at its corner; under it the time and ⌘1–⌘9, or **⏎ Paste** on the card the keys act on. The selection is an accent ring.
- The system accent color (System Settings → Appearance) replaces myClips' orange; orange stays in the app icon.
- Pinboards are small pills; New Pinboard and the menu are plain icons (+ and •••) in the top bar.

## 0.3.0 — 2026-10-13

- Settings, the Clear History alert and the app picker open in front of the active app. Settings opens centered, on the current Space, and Esc closes it.
- Larger text, and one height and shape for the shelf's search field, filter, pinboard chips and buttons. Adding a pinboard no longer moves the top bar.
- Readable card headers: full-white time, a darker teal for links, and dark text on a light color swatch ([#2](https://github.com/sitek94/myclips/issues/2)).
- Settings → About links to the author's site.
- The test hooks (`-uiTest`) exist only in a test build (`UITEST=1 scripts/bundle.sh`), so no other process can open the shelf.
- A new app icon glyph of our own drawing, in the same look (the SF Symbols license does not allow symbols in app icons).

## 0.2.0 — 2026-10-12

- The shortcut that opens the shelf can be changed in Settings → General. Hyper shows as ✦.
- While the search field has text, ⌘A, ⌘C (with text selected), ⌘X, ⌘V, ⌘Z, ⌘⌫ and ⌥ or ⌘ with arrows edit the text instead of acting on the clips ([#1](https://github.com/sitek94/myclips/issues/1)).
- A missing permission shows a yellow warning symbol; the buttons are no longer orange like the selection.
- Settings sections: General, Ignored apps, History, Permissions, About.
- Small changes to the look from shared design tokens: spacing, solid card backgrounds, the copy confirmation.

## 0.1.1 — 2026-10-12

- myClips keeps running when its menu bar icon is hidden in System Settings → Menu Bar; it used to quit. Open the shelf with Hyper+V; Settings and Quit are under its gear button.

## 0.1.0 — 2026-10-11

- Clipboard history with substring search (FTS5 trigram index, accent- and case-insensitive), capped at a configurable number of clips.
- Shelf along the bottom of the screen (Hyper+V) that pastes into the app you were in, with a layout-aware `⌘V`.
- Pinned clips at the front of history, and pinboards.
- Multi-select: paste, copy (`⌘C`), pin or delete several clips; mixed text and images paste as rich text.
- Large preview (`Space` / `⌘Y`) with exact copy time; Quick Look for files.
- Type filter (text, links, images, files) that resets every time the shelf opens.
- Actions menu (`⌘K`), Settings (`⌘,`), ignored apps, and skipping of password managers' concealed copies.
