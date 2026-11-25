#!/bin/bash
# Run on a Mac with a GUI session. Captures the app's own rendered content.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/.amp/in/artifacts/flyout-comparison}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd -P)"
WORK="$(mktemp -d "$OUT/install.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/GitGaze.app"
run_review() {
    local mode="$1"
    rm -f "$OUT/$mode-check.txt" "$OUT/$mode-error.txt"
    args=(--compare-flyout "$mode" "$OUT")
    if [[ "$mode" == reference || "$mode" == shared ]]; then args+=(-palette violet -historyWeeks 53 -menuStreak NO); fi
    open -n -W --stderr "$OUT/$mode-error.txt" "$APP" --args "${args[@]}"
    if [[ ! -f "$OUT/$mode-check.txt" ]]; then cat "$OUT/$mode-error.txt"; exit 1; fi
    cat "$OUT/$mode-check.txt"
}

CONFIGURATION=debug RELEASE_VERSION=1.0.0 "$ROOT/scripts/build.sh"
ditto "$ROOT/.build/GitGaze.app" "$APP"
run_review reference
run_review migration-seed
for key in CFBundleIdentifier SUFeedURL SUPublicEDKey; do
    /usr/libexec/PlistBuddy -c "Print $key" "$APP/Contents/Info.plist" > "$WORK/$key"
done

CONFIGURATION=debug RELEASE_VERSION=1.0.1 "$ROOT/scripts/build.sh"
rm -rf "$APP"
ditto "$ROOT/.build/GitGaze.app" "$APP"
for key in CFBundleIdentifier SUFeedURL SUPublicEDKey; do
    test "$(cat "$WORK/$key")" = "$(/usr/libexec/PlistBuddy -c "Print $key" "$APP/Contents/Info.plist")"
done
echo 'Local bundle replacement retained identifier, feed URL, and Sparkle public key (not a signed Sparkle update).'
run_review migration-upgrade
run_review migration-relaunch
run_review shared
