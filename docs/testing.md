# Testing

## The gate

```sh
scripts/check.sh
```

Runs `swift format lint`, SwiftLint, a build with warnings as errors, and the tests. CI runs the same script. The lint config is a copy of myKit's at the version `Package.resolved` pins: after a myKit update, run `.build/checkouts/mykit/scripts/sync-lint-config.sh`.

## Unit tests

```sh
xcrun swift test
```

Swift Testing, covering `MyClipsCore`: storage, search, pinning, pruning, migrations, capture rules and multi-clip composition. Every bug fix gets a regression test where the logic lives in the core.

## Benchmark

```sh
xcrun swift run -c release MyClipsBench 100000
```

Seeds a throwaway store with synthetic clips and prints p50/p95 search latency for a set of queries. Run it when touching `Store.clips` or the schema.

## UI driver

The app itself is tested by driving the real, signed `myClips.app` — never with your real history.

**`myClipsDriver.app`** is a separate signed app that holds Screen Recording and Accessibility, so the terminal stays unprivileged. It runs as one long-lived process (`scripts/drive.sh` starts it and queues commands), because relaunching it per command disturbed keyboard focus. Grant it once:

```sh
scripts/bundle.sh driver
scripts/drive.sh setup     # then enable myClipsDriver in Screen Recording and Accessibility
```

**Synthetic data and test mode.** `MyClipsSeed` fills a scratch store. Launch flags:

| Flag | Effect |
| --- | --- |
| `-dataDir <dir>` | use a scratch store instead of your history |
| `-paused YES` | don't capture what you copy meanwhile |
| `-uiTest YES` | shelf ignores clicks elsewhere, opens on `drive.sh toggle`, pastes to the clipboard without sending `⌘V` |

```sh
xcrun swift run -c release MyClipsSeed /tmp/myclips-ui
open -g -n build/myClips.app --args -dataDir /tmp/myclips-ui -paused YES -uiTest YES
scripts/drive.sh toggle
scripts/drive.sh type zur
scripts/drive.sh key shift+right
scripts/drive.sh screenshot /tmp/shelf.png      # only myClips' windows are captured
scripts/drive.sh stop
```

In this **safe mode** `key`, `type` and `click` are delivered to the myClips process only, so nothing can reach the apps you're using. (Clicks delivered that way don't reach SwiftUI buttons; test those in an end-to-end run.)

### Gallery

```sh
scripts/gallery.sh [out dir]    # default build/gallery
```

Screenshots of the shelf, a selection, the preview and Settings, in light and dark mode, on synthetic data in safe mode. Use it to review a change to the look, and compare before and after. The installed myClips quits while it runs (about a minute) and restarts at the end.

### End-to-end run

`scripts/e2e.sh` uses real system-wide keys and clicks: Hyper+V, multi-select paste into a throwaway "sink" window, `⌘`-click, the type filter and its reset, and closing on an outside click. **Don't touch the keyboard or mouse while it runs** (about a minute). It aborts before pasting unless the sink window is frontmost, and restarts your real myClips at the end.
