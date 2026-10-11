# Gotchas

Traps hit while building myClips: symptom, cause, fix.

## Building

- **`swift build` rejects the manifest (tools version 6.2, `defaultIsolation`).** A `swift` from another toolchain manager (e.g. swiftly) shadows Xcode's on `PATH`. Use `xcrun swift …`.
- **App icon shows small, inside a grey rounded frame.** macOS 26 does that to plain `.icns` icons. Use an Icon Composer `.icon` document compiled with `actool`, and set `CFBundleIconName` (`scripts/make-icon.swift`, `scripts/bundle.sh`).
- **`open` fails with error -600 right after `pkill`.** The old process hasn't exited yet. Wait for `pgrep` to come back empty before relaunching.
- **SwiftUI `ImageRenderer` in a script fails to compile.** It's main-actor isolated; wrap the script's top level in `MainActor.assumeIsolated`.

## Permissions

- **Permissions reset after a rebuild.** Accessibility and Screen Recording grants belong to the bundle id and signing identity. Sign with a stable identity (any Apple Development certificate); ad-hoc signatures need a re-grant every build. Renaming the bundle id needs a re-grant too.
- **Clipboard reads trigger a system alert.** Since macOS 15.4 apps reading the general pasteboard programmatically are asked about. The app appears in Privacy & Security → Paste from Other Apps only after the first alert; set it to *Always Allow*. `NSPasteboard.accessBehavior` reports the state (`.default` = never asked).
- **Permissions apply to the terminal, not the tool.** A command-line tool launched from a terminal is checked against the terminal's permissions. Wrap the tool in an `.app` and launch it with `open`.

## Focus and windows

- **The panel shows, but typing goes to the app behind it.** A borderless `.nonactivatingPanel` doesn't reliably become key. Add `.titled` and hide the title bar (see [decision 002](decisions/002-non-activating-panel.md)).
- **`NSApp.activate()` does nothing.** macOS 26 activation is cooperative: a background app can't take focus from the active one. Bring a test window forward with `level = .floating` + `orderFrontRegardless()`, and click it.
- **Every single click feels slow.** A `.onTapGesture(count: 2)` next to a single-tap gesture makes SwiftUI hold each click until the double-click interval passes. Use one tap handler and read `NSApp.currentEvent?.clickCount`.
- **A text field doesn't take focus.** Two `@FocusState`s in one window fight over the first responder; use one enum-valued state. A focus state can also still read `true` from the last time a panel was shown — set it to `nil` and back to force it.

## Clipboard and pasting

- **Pasted ⌘V does nothing in a test window.** `NSTextView` pastes through its menu's key equivalent; an app without an Edit menu ignores `⌘V`.
- **Synthetic keys arrive with ⌘ held.** Events from a `.hidSystemState` source inherit modifier state; set `event.flags` explicitly on every event.
- **Screenshots show up as files.** A screenshot copied from its floating thumbnail puts a file URL *and* PNG data on the clipboard. Treat file URL + PNG/JPEG/HEIC as an image.
- **File clips get the wrong thumbnail.** Finder adds the file's *icon* as TIFF to a file copy. Don't use TIFF beside a file URL as the content; use Quick Look on the file.
- **Large images can push a clip over the size cap.** Reading `public.tiff` beside `public.png` makes AppKit convert the image uncompressed (tens of MB). Skip TIFF when PNG is there, and cap per type rather than per clip, so one huge type never drops the whole clip.
- **Terminals paste text only.** Mixed text + image selections paste as RTFD plus plain text; terminals (and Claude Code inside them) take the text only.
