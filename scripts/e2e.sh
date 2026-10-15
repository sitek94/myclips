#!/bin/bash
# End-to-end run with real system-wide keys and clicks. Nobody may touch the Mac while it runs (~1 min).
# Uses a test myClips on synthetic data; pastes only into a throwaway sink window and aborts unless that
# window is frontmost; restarts the installed myClips at the end. See docs/testing.md.
set -uo pipefail
cd "$(dirname "$0")/.."
WORK="${TMPDIR:-/tmp}/myclips-e2e"
SHOTS="$WORK/shots"
D=scripts/drive.sh
R="$WORK/sink.txt"
mkdir -p "$SHOTS"; rm -f "$R"

step() { echo "== $*"; }
# frame <owner> <pattern>: "x y w h id" of the first matching on-screen window.
frame() { $D windows "$1" | grep "$2" | grep "onscreen=1" | head -1 | sed -E 's/id=([0-9]+).*frame=([0-9.]+),([0-9.]+),([0-9.]+),([0-9.]+).*/\2 \3 \4 \5 \1/'; }
# click <window id> <x> <y> [mods]: a global click that the driver refuses unless that window is topmost there.
click() { local id=$1; shift; out=$($D globalclick "$@" "window=$id"); [[ $out == ok ]] || abort "click $*: $out"; }
shelf() { $D windows myClips | grep layer=3 | grep -E "frame=[0-9.]+,[0-9.]+,[0-9]{4}" | grep -o "onscreen=[a-z0-9]*" | head -1; }
restore() { pkill -x myClips; while pgrep -x myClips >/dev/null; do sleep 0.1; done; open ~/Applications/myClips.app; echo "installed myClips restarted"; }
sink_front() { $D front | grep -q "dev.maciek.myclips.driver"; }
abort() { echo "ABORT: $*"; restore; exit 1; }

step "build and seed"
UITEST=1 scripts/bundle.sh >/dev/null && scripts/bundle.sh driver >/dev/null || exit 1
xcrun swift build -c release --product MyClipsSeed >/dev/null && .build/release/MyClipsSeed "$WORK/data" >/dev/null || exit 1

step "test myClips (paused, synthetic data)"
pkill -x myClips; while pgrep -x myClips >/dev/null; do sleep 0.1; done
open -g -n build/myClips.app --args -dataDir "$WORK/data" -paused YES
until pgrep -x myClips >/dev/null; do sleep 0.2; done; sleep 1

step "sink to front"
open -n build/myClipsDriver.app --args sinkapp "$R" 60
sleep 2
read -r SX SY _ _ SID <<<"$(frame myClipsDriver 'frame=200,')"
[[ -n "${SX:-}" ]] || abort "no sink window"
click "$SID" $((${SX%.*} + 200)) $((${SY%.*} + 100)); sleep 0.6
sink_front || abort "sink not frontmost ($($D front))"

step "multi-select paste: Hyper+V, shift+right x2, Return"
$D globalkey ctrl+opt+shift+cmd+v >/dev/null; sleep 0.7
$D globalkey shift+right >/dev/null; $D globalkey shift+right >/dev/null; sleep 0.3
sink_front || abort "front is $($D front) before Return"
$D globalkey return >/dev/null; sleep 1.2

step "cmd-click cards 1 and 3"
$D globalkey ctrl+opt+shift+cmd+v >/dev/null; sleep 0.7
read -r X Y _ _ ID <<<"$(frame myClips 'layer=3')"
[[ -n "${X:-}" ]] || abort "shelf did not open"
# The centers of the first and third cards' boxes (cells 255 wide from x 20, a pinned rule after the first).
click "$ID" $((${X%.*} + 147)) $((${Y%.*} + 130)); sleep 0.2
click "$ID" $((${X%.*} + 660)) $((${Y%.*} + 130)) cmd; sleep 0.3
$D screenshot "$SHOTS/cmd-click.png" >/dev/null

step "type filter: Images, then reset on reopen"
click "$ID" $((${X%.*} + 325)) $((${Y%.*} + 27)); sleep 0.6
for _ in 1 2 3 4; do $D globalkey down >/dev/null; done
$D globalkey return >/dev/null; sleep 0.6
$D screenshot "$SHOTS/images-only.png" >/dev/null
$D globalkey esc >/dev/null; sleep 0.4
$D globalkey ctrl+opt+shift+cmd+v >/dev/null; sleep 0.7
$D screenshot "$SHOTS/reopened.png" >/dev/null

step "outside click closes the shelf"
echo -n "before: "; shelf
click "$SID" $((${SX%.*} + 200)) $((${SY%.*} + 100)); sleep 0.6
echo -n "after: "; shelf

step "sink result (expect three seeded clips, one per line)"
until [[ -e "$R" ]]; do sleep 0.5; done
cat "$R"; echo
echo "screenshots: $SHOTS"
restore
