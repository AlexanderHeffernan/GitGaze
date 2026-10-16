#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
swift build --package-path "$ROOT" -c "$CONFIGURATION"
BIN="$(swift build --package-path "$ROOT" -c "$CONFIGURATION" --show-bin-path)"
APP="$ROOT/.build/GitGlaze.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/GitGlaze" "$APP/Contents/MacOS/GitGlaze"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
swift "$ROOT/scripts/icon.swift" "$APP/Contents/Resources"
codesign --force --sign "${CODESIGN_IDENTITY:--}" "$APP"
echo "Built $APP"
if [ "${1:-}" = "--install" ]; then
    mkdir -p "$HOME/Applications"
    ditto "$APP" "$HOME/Applications/GitGlaze.app"
    echo "Installed $HOME/Applications/GitGlaze.app"
fi
