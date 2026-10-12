# Gotchas

Traps hit while building myClips: symptom, cause, fix.

Traps that any macOS 26 app built this way hits (building, the icon, permissions, focus and windows, global shortcuts, synthetic input, UI testing) are in [myKit's gotchas](https://github.com/sitek94/mykit/blob/main/docs/gotchas.md). This page has the clipboard ones.

## Clipboard and pasting

- **Pasted ⌘V does nothing in a test window.** `NSTextView` pastes through its menu's key equivalent; an app without an Edit menu ignores `⌘V`.
- **Screenshots show up as files.** A screenshot copied from its floating thumbnail puts a file URL *and* PNG data on the clipboard. Treat file URL + PNG/JPEG/HEIC as an image.
- **File clips get the wrong thumbnail.** Finder adds the file's *icon* as TIFF to a file copy. Don't use TIFF beside a file URL as the content; use Quick Look on the file.
- **Large images can push a clip over the size cap.** Reading `public.tiff` beside `public.png` makes AppKit convert the image uncompressed (tens of MB). Skip TIFF when PNG is there, and cap per type rather than per clip, so one huge type never drops the whole clip.
- **Terminals paste text only.** Mixed text + image selections paste as RTFD plus plain text; terminals (and Claude Code inside them) take the text only.
