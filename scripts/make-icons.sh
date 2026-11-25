#!/usr/bin/env bash
# Regenerates the app icons and the website mark from ui/js/mark.js.
# macOS icons keep Apple's transparent margin (art 824 of 1024); Windows icons fill the square.
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
writeFileSync('src-tauri/icons/icon.svg', icon + '\n');
writeFileSync('$TMP/mac.svg', icon.replace('<rect', '<g transform=\"translate(17.58 17.58) scale(0.8047)\"><rect').replace(/<\/svg>$/, '</g></svg>'));
writeFileSync('site/mark.svg', markSVG(green, { size: 64 }) + '\n');
"

npx tauri icon src-tauri/icons/icon.svg -o "$TMP/full" >/dev/null 2>&1
npx tauri icon "$TMP/mac.svg" -o "$TMP/mac" >/dev/null 2>&1
cp "$TMP/full/"{32x32.png,128x128.png,128x128@2x.png,icon.png,icon.ico} src-tauri/icons/
cp "$TMP/mac/icon.icns" src-tauri/icons/
