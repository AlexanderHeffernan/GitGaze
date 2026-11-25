#!/bin/bash
# Install the latest public Stoke release for this user. No sudo or quarantine stripping.
# Stoke was called GitGaze until 1.1.7; an installed GitGaze.app is replaced.
set -euo pipefail
REPO="AlexanderHeffernan/Stoke"
INSTALL_DIR="$HOME/Applications"
NAME=Stoke
ARCHIVE="$NAME.zip"
DEST="$INSTALL_DIR/$NAME.app"
LEGACY="$INSTALL_DIR/GitGaze.app"
BASE="https://github.com/$REPO/releases/latest/download"
mkdir -p "$INSTALL_DIR"
STAGE="$(mktemp -d "$INSTALL_DIR/.stoke-install.XXXXXX")"
cleanup() {
    if [ -d "$STAGE/previous.app" ] && [ ! -e "$DEST" ]; then
        mv "$STAGE/previous.app" "$DEST" || { echo "Previous app preserved at $STAGE/previous.app" >&2; return; }
    fi
    rm -rf "$STAGE"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP
ours() { [ ! -L "$1" ] && [ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null)" = app.gitbar.mac ]; }
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "$BASE/$ARCHIVE" -o "$STAGE/$ARCHIVE"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "$BASE/SHA256SUMS" -o "$STAGE/SHA256SUMS"
CHECKSUM="$(awk -v file="$ARCHIVE" '$2 == file {print}' "$STAGE/SHA256SUMS")"
[[ "$CHECKSUM" =~ ^[[:xdigit:]]{64}[[:space:]]+$NAME\.zip$ ]] || { echo "Invalid release checksum" >&2; exit 1; }
printf '%s\n' "$CHECKSUM" > "$STAGE/archive.sha256"
(cd "$STAGE" && shasum -a 256 -c archive.sha256)
ditto -x -k "$STAGE/$ARCHIVE" "$STAGE/unpacked"
APP="$STAGE/unpacked/$NAME.app"
ours "$APP" || exit 1
[ -x "$APP/Contents/MacOS/$NAME" ] || exit 1
codesign --verify --deep --strict "$APP"
if [ -e "$DEST" ] && ! ours "$DEST"; then
    echo "Refusing to replace an unrelated app or symlink at $DEST" >&2
    exit 1
fi
running() { pgrep -x "$NAME" >/dev/null || pgrep -x GitGaze >/dev/null; }
if running; then
    osascript -e 'tell application id "app.gitbar.mac" to quit'
    for ((i=0; i<40; i++)); do
        running || break
        sleep 0.25
    done
    if running; then
        echo "$NAME is still closing. Quit it before running the installer again." >&2
        exit 1
    fi
fi
if [ -e "$DEST" ]; then mv "$DEST" "$STAGE/previous.app"; fi
mv "$APP" "$DEST"
if [ "$LEGACY" != "$DEST" ] && [ -e "$LEGACY" ] && ours "$LEGACY"; then rm -rf "$LEGACY"; fi
echo "Installed $DEST. Future updates are available in Settings → Updates."
open -n "$DEST"
