#!/bin/bash
# Drives the UI through myClipsDriver.app, which holds Screen Recording + Accessibility.
# A single driver process serves all commands, so focus is not disturbed by relaunches.
# usage: scripts/drive.sh <verb> [args...]    (verbs: see Sources/MyClipsDriver/main.swift)
#        scripts/drive.sh stop                quit the driver
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/myClipsDriver.app
DIR="${TMPDIR:-/tmp}/clips-driver"

if [[ "${1:-}" == "stop" ]]; then
    pkill -f "myClipsDriver serve" || true
    exit
fi
if [[ ! -d "$APP" ]]; then
    scripts/bundle.sh driver >/dev/null
fi
if ! pgrep -f "myClipsDriver serve" >/dev/null; then
    mkdir -p "$DIR/req" "$DIR/res"
    open -g -n "$APP" --args serve "$DIR"
    for _ in $(seq 1 50); do pgrep -f "myClipsDriver serve" >/dev/null && break; sleep 0.1; done
fi

id=$(date +%s%N)-$$
python3 -I -c 'import json, sys; print(json.dumps(sys.argv[1:]))' "$@" > "$DIR/req/$id.tmp"
mv "$DIR/req/$id.tmp" "$DIR/req/$id.json"
for _ in $(seq 1 300); do [[ -e "$DIR/res/$id.txt" ]] && break; sleep 0.05; done
[[ -e "$DIR/res/$id.txt" ]] || { echo "myClipsDriver did not answer"; exit 1; }
code=$(head -1 "$DIR/res/$id.txt")
tail -n +2 "$DIR/res/$id.txt"; echo
rm -f "$DIR/res/$id.txt"
exit "$code"
