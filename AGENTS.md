# myClips agent index

myClips is a personal clipboard manager for macOS 26 (Swift 6, SwiftUI + AppKit, SQLite). Keep the feature set small.

`scripts/check.sh` is the gate: format, lint (including the design-token rules from myKit), build with warnings as errors, tests. CI runs the same script. Always go through `xcrun`: a `swift` elsewhere on `PATH` may be an older toolchain.

This file is a map, not the docs. Open the page that owns the task:

- How it works — storage, search, capture, the shelf, pasting: [docs/architecture.md](./docs/architecture.md)
- Testing, benchmark, driving the UI: [docs/testing.md](./docs/testing.md)
- Traps and their fixes: [docs/gotchas.md](./docs/gotchas.md)
- Why search, the shelf and UI testing work this way: [docs/decisions/](./docs/decisions/)

## Rules

- The real store (`~/Library/Application Support/dev.maciek.myclips/clips.sqlite`) holds the user's clipboard, secrets included. Never print rows — counts and schema only.
- UI work runs on synthetic data in safe mode (docs/testing.md). System-wide keys and clicks only with the user's go-ahead and hands off the Mac.
- Bug fixes get a regression test; schema changes get a migration step and an upgrade test.
- New version: bump `VERSION` in `scripts/bundle.sh`, list user-visible changes under a new heading in [CHANGELOG.md](./CHANGELOG.md), tag `vX.Y.Z`.
- Clean room: no code, assets or text from Paste or other apps.
