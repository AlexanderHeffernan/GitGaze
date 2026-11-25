#!/bin/bash
# Assembles and signs release assets from the CI build artifacts. Never uploads or publishes.
#   package-release.sh VERSION ARTIFACTS_DIR OUTPUT_DIR
# Requires SPARKLE_PRIVATE_KEY (the existing Sparkle Ed25519 key), which signs both update paths:
# - appcast.xml + GitGaze.zip: the final Sparkle update for installs of 1.0.x.
# - latest.json: the built-in updater on macOS (GitGaze.app.tar.gz) and Windows (setup .exe).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?Usage: package-release.sh VERSION ARTIFACTS OUTPUT}"
ARTIFACTS="$(cd "${2:?}" && pwd)"
OUT="${3:?}"
BASE="https://github.com/AlexanderHeffernan/GitGaze/releases/download/v$VERSION"
SPARKLE_VERSION=2.10.0
rm -rf "$OUT" && mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
find "$ARTIFACTS" -type f \( -name 'GitGaze.zip' -o -name 'GitGaze.app.tar.gz' -o -name 'GitGaze-windows-*-setup.exe' \) -exec cp {} "$OUT/" \;
for file in GitGaze.zip GitGaze.app.tar.gz GitGaze-windows-x64-setup.exe GitGaze-windows-arm64-setup.exe; do
    test -s "$OUT/$file" || { echo "Missing $file" >&2; exit 1; }
done

# Release notes from merged changes since the previous release.
gh api --method POST "repos/AlexanderHeffernan/GitGaze/releases/generate-notes" \
    -f tag_name="v$VERSION" -f target_commitish="${GITHUB_SHA:-HEAD}" --jq .body > "$OUT/notes.md" || echo "GitGaze $VERSION" > "$OUT/notes.md"

# Sparkle feed for existing 1.0.x installs, signed with Sparkle's own tool.
TOOLS="$(mktemp -d)"
curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" | tar -xJ -C "$TOOLS"
FEED="$(mktemp -d)"
cp "$OUT/GitGaze.zip" "$FEED/"
cp "$OUT/notes.md" "$FEED/GitGaze.md"
printf '%s' "$SPARKLE_PRIVATE_KEY" | "$TOOLS/bin/generate_appcast" --ed-key-file - --embed-release-notes --maximum-deltas 0 \
    --download-url-prefix "$BASE/" --link "https://github.com/AlexanderHeffernan/GitGaze" "$FEED"
cp "$FEED/appcast.xml" "$OUT/appcast.xml"
python3 "$ROOT/scripts/release.py" verify "$OUT" "$VERSION"
SIGNATURE="$(python3 -c "import re,sys; print(re.search(r'edSignature=\"([^\"]+)\"', open(sys.argv[1]).read()).group(1))" "$OUT/appcast.xml")"
python3 "$ROOT/scripts/sign_update.py" verify "$OUT/GitGaze.zip" "$SIGNATURE"
grep -q 'sparkle-signatures' "$OUT/appcast.xml" || { echo 'The appcast is not signed' >&2; exit 1; }

# Tauri updater manifest.
sign() { python3 "$ROOT/scripts/sign_update.py" sign "$OUT/$1" "$VERSION"; }
MAC="$(sign GitGaze.app.tar.gz)"
WIN_X64="$(sign GitGaze-windows-x64-setup.exe)"
WIN_ARM="$(sign GitGaze-windows-arm64-setup.exe)"
python3 - "$OUT/latest.json" "$VERSION" "$BASE" "$MAC" "$WIN_X64" "$WIN_ARM" "$OUT/notes.md" <<'PY'
import json, sys, datetime
path, version, base, mac, x64, arm, notes = sys.argv[1:]
entry = lambda signature, name: {"signature": signature, "url": f"{base}/{name}"}
platforms = {
    "darwin-aarch64": entry(mac, "GitGaze.app.tar.gz"),
    "darwin-x86_64": entry(mac, "GitGaze.app.tar.gz"),
    "windows-x86_64": entry(x64, "GitGaze-windows-x64-setup.exe"),
    "windows-aarch64": entry(arm, "GitGaze-windows-arm64-setup.exe"),
}
json.dump({"version": version, "notes": open(notes).read(), "pub_date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
           "platforms": platforms}, open(path, "w"), indent=2)
PY
(cd "$OUT" && shasum -a 256 GitGaze.zip GitGaze.app.tar.gz GitGaze-windows-x64-setup.exe GitGaze-windows-arm64-setup.exe appcast.xml latest.json > SHA256SUMS)
echo "Release assets ready in $OUT (not published)"
