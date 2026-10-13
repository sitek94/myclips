#!/bin/bash
# Draws the app icon: our own glyph (scripts/Glyph.swift, via scripts/make-glyph.swift) on the brand
# gradient, as an Icon Composer document in Resources/AppIcon.icon. bundle.sh compiles it.
set -euo pipefail
cd "$(dirname "$0")/.."
mykit=$([[ -d Packages/mykit ]] && echo Packages/mykit || echo .build/checkouts/mykit)
tmp=$(mktemp -d)
xcrun swiftc -parse-as-library -O scripts/Glyph.swift scripts/make-glyph.swift -o "$tmp/make-glyph"
"$tmp/make-glyph" "$tmp/glyph.png"
xcrun swift "$mykit/scripts/make-icon.swift" "$PWD/Resources/AppIcon.icon" FB923C EA580C "$tmp/glyph.png"
