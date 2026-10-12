#!/bin/bash
# Builds, bundles and signs myClips.app.
#   scripts/bundle.sh           build build/myClips.app
#   scripts/bundle.sh install   also copy to ~/Applications and launch
#   scripts/bundle.sh driver    build build/myClipsDriver.app (UI test driver)
# Signing with a stable identity keeps Accessibility, clipboard and Screen Recording grants across rebuilds.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${MYCLIPS_SIGN_IDENTITY:-Apple Development}"
# Bump with every tagged version (see CHANGELOG.md).
VERSION=0.1.1
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
[[ -n "$(git status --porcelain 2>/dev/null)" ]] && COMMIT="$COMMIT-dirty"

# bundle <product> <bundle id>
bundle() {
    local product=$1 id=$2 app=build/$1.app
    xcrun swift build -c release --product "$product"
    rm -rf "$app"
    mkdir -p "$app/Contents/MacOS"
    cp ".build/release/$product" "$app/Contents/MacOS/$product"
    if [[ -n "${icon:-}" ]]; then
        # Icon Composer document -> Assets.car (+ fallback .icns); macOS 26 renders it natively.
        mkdir -p "$app/Contents/Resources"
        xcrun actool "$icon" --compile "$app/Contents/Resources" --platform macosx \
            --minimum-deployment-target 26.0 --app-icon AppIcon \
            --output-partial-info-plist "$(mktemp -d)/partial.plist" >/dev/null
    fi
    cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>$id</string>
    <key>CFBundleName</key><string>$product</string>
    <key>CFBundleExecutable</key><string>$product</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>GitCommit</key><string>$COMMIT</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>NSHumanReadableCopyright</key><string>Personal build</string>
</dict>
</plist>
PLIST
    codesign --force --options runtime --sign "$IDENTITY" "$app"
    codesign --verify --strict "$app"
    echo "built $app"
}

if [[ "${1:-}" == "driver" ]]; then
    bundle myClipsDriver dev.maciek.myclips.driver
    exit
fi

icon=Resources/AppIcon.icon bundle myClips dev.maciek.myclips

if [[ "${1:-}" == "install" ]]; then
    pkill -x myClips || true
    while pgrep -x myClips >/dev/null; do sleep 0.1; done
    mkdir -p ~/Applications
    rm -rf ~/Applications/myClips.app
    cp -R build/myClips.app ~/Applications/myClips.app
    # LaunchServices can still hold the old instance for a moment after it exits (error -600).
    open ~/Applications/myClips.app || { sleep 1; open ~/Applications/myClips.app; }
    echo "installed ~/Applications/myClips.app"
fi
