#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
INSTALL=false
BUILD=(--package-path "$ROOT" -c "$CONFIGURATION")
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=true ;;
        --universal) BUILD+=(--arch arm64 --arch x86_64) ;;
        *) echo "Usage: $0 [--install] [--universal]" >&2; exit 2 ;;
    esac
done
swift build "${BUILD[@]}"
BIN="$(swift build "${BUILD[@]}" --show-bin-path)"
APP="$ROOT/.build/GitGaze.app"
# Always package a fresh bundle; stale files invalidate signatures and updates.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/GitGaze" "$APP/Contents/MacOS/GitGaze"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
if [ -n "${RELEASE_VERSION:-}" ]; then
    [[ "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid release version" >&2; exit 1; }
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $RELEASE_VERSION" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $RELEASE_VERSION" "$APP/Contents/Info.plist"
fi
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
ditto "$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$FRAMEWORK"
cp "$ROOT/.build/artifacts/sparkle/Sparkle/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"
swift "$ROOT/scripts/icon.swift" "$APP/Contents/Resources"
SIGN=(--force --sign "${CODESIGN_IDENTITY:--}")
if [ "${CODESIGN_IDENTITY:--}" != "-" ]; then
    SIGN+=(--options runtime --timestamp)
    # Sign nested code inside-out, not with codesign --deep.
    for component in XPCServices/Downloader.xpc XPCServices/Installer.xpc Autoupdate Updater.app; do
        codesign "${SIGN[@]}" "$FRAMEWORK/Versions/B/$component"
    done
    codesign "${SIGN[@]}" "$FRAMEWORK"
fi
codesign "${SIGN[@]}" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP"
if [ "$INSTALL" = true ]; then
    mkdir -p "$HOME/Applications"
    ditto "$APP" "$HOME/Applications/GitGaze.app"
    echo "Installed $HOME/Applications/GitGaze.app"
fi
