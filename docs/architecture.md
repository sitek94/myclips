# Architecture

Two layers:

- **MyClipsCore** — no UI. SQLite storage and search (`Store`), capture decisions (`CaptureRules`), composing several clips into one clipboard item (`MultiClip`). Fully unit tested.
- **MyClips** — the app: a menu bar extra, the shelf (`PanelController`, `PanelView`, `PanelModel`), preview, settings, the pasteboard watcher and the paster. Main-actor by default (`defaultIsolation(MainActor.self)`); only `Store` is an actor.

## Storage and search

One SQLite file (`~/Library/Application Support/dev.maciek.myclips/clips.sqlite`), WAL mode, schema version in `PRAGMA user_version` with step-by-step migrations in `Store.migrate`.

- `items`: one row per clip — kind, searchable text, source app, timestamps, `pinned_at`.
- `reps`: every pasteboard type of every pasteboard item, as bytes. Pasting writes them all back, so rich text, images and files round-trip.
- `items_fts`: FTS5 with the `trigram` tokenizer and `remove_diacritics`, so any substring of 3+ characters matches, ignoring case and accents. Shorter tokens fall back to `LIKE`.
- `pinboards`, `pinboard_items`: collections. Clips on a pinboard, and pinned clips, never expire.

**Ids are recency.** Using a clip again (re-copying or pasting it) moves it to a new highest id; foreign keys follow via `ON UPDATE CASCADE` and a trigger keeps the FTS row in step. A history search can then walk the FTS index by `rowid DESC` and stop after 200 hits instead of sorting every match. At 100,000 clips that took common-word searches from ~65 ms to under 1 ms. Pinned clips are a separate small query placed first.

## Capture

`PasteboardWatcher` polls `NSPasteboard.changeCount` every 0.25 s (there is no change notification). On a change it:

1. skips changes myClips made itself (it records the change count after writing);
2. skips ignored apps (the frontmost app's bundle id; password managers built in, more in Settings);
3. skips content marked with the [nspasteboard.org](http://nspasteboard.org) concealed/transient/auto-generated types;
4. reads the types worth keeping (`CaptureRules.typesToRead`: no `dyn.` types, no legacy aliases, no TIFF beside PNG) within size caps (10 MB per type, 20 MB per clip — oversized types are dropped, not the clip);
5. classifies it (`CaptureRules.kind`) and records it; an identical clip moves to the top instead of duplicating.

macOS 26 asks before an app reads the clipboard programmatically. myClips needs *Always Allow* under Privacy & Security → Paste from Other Apps.

## The shelf

A myKit `FloatingPanel` (a titled, non-activating `NSPanel` with the title bar hidden; see [decision 002](decisions/002-non-activating-panel.md)) placed along the bottom of the screen under the mouse. It takes keyboard focus **without activating myClips**, so the app you were in stays frontmost and receives the paste.

- Keys go through one local event monitor in `PanelController.handle`; letters are matched by character so shortcuts follow the keyboard layout.
- It closes on `Esc`, the hotkey, a paste, a click outside or another app activating — but not when the screenshot UI (`screencaptureui`) is up, so you can screenshot it. `FloatingPanel` watches the clicks and app switches; `PanelController` handles the keys.
- One `FocusState` for the whole panel; separate ones fought over the first responder.
- One tap handler per card reads the click count; a separate double-tap gesture delayed every single click.

The global shortcut is a myKit `GlobalShortcut` (Carbon's `RegisterEventHotKey`, which needs no permission). It is ✦ V (Hyper+V) by default; Settings → General changes it.

## Pasting

1. Write the clip to the clipboard: all its stored types; or plain text; or, for several clips, one item with their texts joined plus RTFD with images in order (`MultiClip`).
2. Record that change count so the watcher ignores it.
3. Hide the shelf, hand focus back to the previous app if myClips somehow became active, and post `⌘V` with `CGEvent`. The key code for "v" is looked up in the current keyboard layout, so it works on Dvorak, AZERTY and others. This needs Accessibility; without it the clip simply stays on the clipboard.
