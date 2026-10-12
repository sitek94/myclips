#!/bin/bash
# Screenshots of the main surfaces in light and dark mode, on synthetic data, for a look review.
# Safe mode: keys go to the test myClips only, and only its windows are captured. The installed myClips
# quits for about a minute (the driver talks to one myClips process) and restarts at the end.
# usage: scripts/gallery.sh [out dir]    (default build/gallery)
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-build/gallery}"
WORK="${TMPDIR:-/tmp}/myclips-gallery"
D=scripts/drive.sh
mkdir -p "$OUT" && OUT="$(cd "$OUT" && pwd)"  # the driver runs elsewhere

quit() { pkill -x myClips; while pgrep -x myClips >/dev/null; do sleep 0.1; done; }
# LaunchServices can still hold the old instance for a moment after it exits (error -600).
restore() { quit; open ~/Applications/myClips.app || { sleep 1; open ~/Applications/myClips.app; }; echo "installed myClips restarted"; }
trap restore EXIT

scripts/bundle.sh >/dev/null && scripts/bundle.sh driver >/dev/null || exit 1
rm -rf "$WORK" && xcrun swift build -c release --product MyClipsSeed >/dev/null && .build/release/MyClipsSeed "$WORK" >/dev/null || exit 1

for mode in light dark; do
    quit
    style=()
    [[ $mode == dark ]] && style=(-AppleInterfaceStyle Dark)
    open -g -n build/myClips.app --args -dataDir "$WORK" -paused YES -uiTest YES ${style[@]+"${style[@]}"}
    until pgrep -x myClips >/dev/null; do sleep 0.2; done; sleep 1.5
    $D toggle >/dev/null; sleep 1
    $D screenshot "$OUT/shelf-$mode.png"
    $D key right >/dev/null; $D key shift+right >/dev/null; sleep 0.5
    $D screenshot "$OUT/selection-$mode.png"
    $D key space >/dev/null; sleep 0.8
    $D screenshot "$OUT/preview-$mode.png"
    $D key esc >/dev/null; sleep 0.3
    $D key cmd+n >/dev/null; sleep 0.5
    $D screenshot "$OUT/new-pinboard-$mode.png"
    $D key esc >/dev/null; sleep 0.3
    $D key cmd+comma >/dev/null; sleep 1.2
    $D screenshot "$OUT/settings-$mode.png"
done
$D stop
echo "gallery: $OUT"
