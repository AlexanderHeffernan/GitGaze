#!/bin/bash
# Install the latest public GitGaze release for this user. No sudo or quarantine stripping.
set -euo pipefail
INSTALL_DIR="$HOME/Applications"
DEST="$INSTALL_DIR/GitGaze.app"
BASE="https://github.com/AlexanderHeffernan/GitGaze/releases/latest/download"
mkdir -p "$INSTALL_DIR"
STAGE="$(mktemp -d "$INSTALL_DIR/.gitgaze-install.XXXXXX")"
cleanup() {
    if [ -d "$STAGE/previous.app" ] && [ ! -e "$DEST" ]; then
        mv "$STAGE/previous.app" "$DEST" || { echo "Previous app preserved at $STAGE/previous.app" >&2; return; }
    fi
    rm -rf "$STAGE"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "$BASE/GitGaze.zip" -o "$STAGE/GitGaze.zip"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "$BASE/SHA256SUMS" -o "$STAGE/SHA256SUMS"
CHECKSUM="$(awk '$2 == "GitGaze.zip" {print}' "$STAGE/SHA256SUMS")"
[[ "$CHECKSUM" =~ ^[[:xdigit:]]{64}[[:space:]]+GitGaze.zip$ ]] || { echo "Invalid release checksum" >&2; exit 1; }
printf '%s\n' "$CHECKSUM" > "$STAGE/archive.sha256"
(cd "$STAGE" && shasum -a 256 -c archive.sha256)
ditto -x -k "$STAGE/GitGaze.zip" "$STAGE/unpacked"
APP="$STAGE/unpacked/GitGaze.app"
[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")" = app.gitbar.mac ] || exit 1
[ -x "$APP/Contents/MacOS/GitGaze" ] || exit 1
codesign --verify --deep --strict "$APP"
if [ -e "$DEST" ]; then
    [ ! -L "$DEST" ] && [ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$DEST/Contents/Info.plist")" = app.gitbar.mac ] \
        || { echo "Refusing to replace an unrelated app or symlink at $DEST" >&2; exit 1; }
fi
if pgrep -x GitGaze >/dev/null; then
    osascript -e 'tell application id "app.gitbar.mac" to quit'
fi
if [ -e "$DEST" ]; then mv "$DEST" "$STAGE/previous.app"; fi
mv "$APP" "$DEST"
echo "Installed $DEST. Future updates are available in Settings → Updates."
open "$DEST"
