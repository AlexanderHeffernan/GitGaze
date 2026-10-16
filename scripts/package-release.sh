#!/bin/bash
# Creates local release assets only. Never uploads or publishes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?Usage: package-release.sh VERSION}"
OUT="$ROOT/.build/distribution"
TOOLS="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
RELEASE_VERSION="$VERSION" "$ROOT/scripts/build.sh" --universal
"$ROOT/.build/GitGaze.app/Contents/MacOS/GitGaze" --smoke-test
rm -rf "$OUT"
mkdir -p "$OUT"
ditto -c -k --sequesterRsrc --keepParent "$ROOT/.build/GitGaze.app" "$OUT/GitGaze.zip"
if [ -n "${NOTARY_PROFILE:-}" ]; then
    NOTARY=(--keychain-profile "$NOTARY_PROFILE")
    if [ -n "${NOTARY_KEYCHAIN:-}" ]; then NOTARY+=(--keychain "$NOTARY_KEYCHAIN"); fi
    xcrun notarytool submit "$OUT/GitGaze.zip" "${NOTARY[@]}" --wait
    xcrun stapler staple "$ROOT/.build/GitGaze.app"
    spctl --assess --type execute --verbose "$ROOT/.build/GitGaze.app"
    rm "$OUT/GitGaze.zip"
    ditto -c -k --sequesterRsrc --keepParent "$ROOT/.build/GitGaze.app" "$OUT/GitGaze.zip"
fi
SIGNING=(--account GitGaze)
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then SIGNING=(--ed-key-file -); fi
if [ -n "${RELEASE_NOTES_FILE:-}" ]; then cp "$RELEASE_NOTES_FILE" "$OUT/GitGaze.md"; fi
printf '%s' "${SPARKLE_PRIVATE_KEY:-}" | "$TOOLS/generate_appcast" "${SIGNING[@]}" \
    --embed-release-notes --maximum-deltas 0 --download-url-prefix "https://github.com/AlexanderHeffernan/GitGaze/releases/download/v$VERSION/" \
    --link "https://github.com/AlexanderHeffernan/GitGaze" "$OUT"
python3 "$ROOT/scripts/release.py" verify "$OUT" "$VERSION"
PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$ROOT/.build/GitGaze.app/Contents/Info.plist")"
swift "$ROOT/scripts/verify-update.swift" "$OUT" "$PUBLIC_KEY"
(cd "$OUT" && shasum -a 256 GitGaze.zip appcast.xml > SHA256SUMS)
echo "Release assets ready in $OUT (not published)"
