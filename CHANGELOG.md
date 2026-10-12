# Changelog

## Unreleased

- Larger text and controls on the shelf.

- The shelf's search field, filter, pinboard chips and buttons have one height and shape. Adding a pinboard no longer moves the shelf's top bar.

- Settings, the Clear History alert and the app picker open in front of the active app. Settings opens centered, on the current Space, and Esc closes it.
- The time on card headers shows in full white, for contrast.

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
