# Changelog

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
