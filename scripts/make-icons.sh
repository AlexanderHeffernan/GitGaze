#!/usr/bin/env bash
# Regenerates the app icons and the website mark from ui/js/mark.js.
# macOS icons keep Apple's transparent margin (art 824 of 1024); Windows icons fill the square.
# Sizes up to 48 pixels use the compact mark, whose fewer, larger squares stay legible.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$ROOT"

node --input-type=module -e "
import { writeFileSync } from 'node:fs';
import { markSVG } from './ui/js/mark.js';
const green = [0.25, 0.77, 0.39];
const icon = markSVG(green, { size: 1024, tile: '#0d1117' });
const small = markSVG(green, { size: 1024, tile: '#0d1117', compact: true });
writeFileSync('src-tauri/icons/icon.svg', icon + '\n');
writeFileSync('$TMP/small.svg', small);
writeFileSync('$TMP/mac.svg', icon.replace('<rect', '<g transform=\"translate(17.58 17.58) scale(0.8047)\"><rect').replace(/<\/svg>$/, '</g></svg>'));
writeFileSync('site/mark.svg', markSVG(green, { size: 64, tile: '#0d1117', compact: true }) + '\n');
"

npx tauri icon src-tauri/icons/icon.svg -o "$TMP/full" >/dev/null 2>&1
npx tauri icon src-tauri/icons/icon.svg -o "$TMP/large" -p 64,256 >/dev/null 2>&1
npx tauri icon "$TMP/small.svg" -o "$TMP/small" -p 16,24,32,48 >/dev/null 2>&1
npx tauri icon "$TMP/mac.svg" -o "$TMP/mac" >/dev/null 2>&1
cp "$TMP/full/"{128x128.png,128x128@2x.png,icon.png} src-tauri/icons/
cp "$TMP/small/32x32.png" src-tauri/icons/
# Pillow stores each size as PNG, keeping the icon small; each size keeps its own drawing.
uv run --quiet --with pillow python3 - "$TMP" <<'PY'
import sys
from PIL import Image
tmp = sys.argv[1]
files = [f"{tmp}/small/{n}x{n}.png" for n in (16, 24, 32, 48)] + [f"{tmp}/large/{n}x{n}.png" for n in (64, 256)]
images = [Image.open(f) for f in files]
images[-1].save("src-tauri/icons/icon.ico", sizes=[i.size for i in images], append_images=images[:-1])
PY
cp "$TMP/mac/icon.icns" src-tauri/icons/
