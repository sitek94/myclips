# UI testing through a separate signed driver app

Date: 2026-10-11

Status: accepted

## Context

Most of myClips' risk is in its interaction with macOS — focus, key routing, the clipboard, pasting into another app — which unit tests can't reach. Testing it means taking screenshots and sending keys and clicks. Doing that from a terminal requires granting the terminal Screen Recording and Accessibility, which then applies to everything run in it. It also happens on a Mac someone is using: system-wide keystrokes can land in their apps, and screenshots can show their real clipboard.

## Decision

- **`myClipsDriver.app`**, a separate app signed with the same identity, holds Screen Recording and Accessibility. It runs as one long-lived process that executes queued commands (`scripts/drive.sh`). Relaunching it per command disturbed keyboard focus.
- **Fixed verbs only** (`screenshot`, `key`, `type`, `click`, `windows`, …) — no "run this command" verb that would turn it into a general way around macOS permissions.
- **Safe mode by default:** `key`, `type` and `click` are posted to the myClips process only (`CGEvent.postToPid`); screenshots include only myClips' windows.
- **Test launches of myClips** use synthetic data (`MyClipsSeed`, `-dataDir`), don't capture (`-paused YES`), and with `-uiTest YES` open on a notification and skip sending `⌘V`.
- **System-wide events** (`globalkey`, `globalclick`, `scripts/e2e.sh`) only with the user hands-off. The end-to-end script pastes into a throwaway window and aborts unless that window is frontmost.

## Consequences

- The real app can be tested while someone works on the Mac, without touching their apps or data.
- Clicks posted to a process don't reach SwiftUI buttons, so clicking is only covered by the hands-off end-to-end run.
- The driver's permissions survive rebuilds only because its bundle id and signing identity stay the same.
