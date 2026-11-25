#!/bin/bash
# Run on a Mac with a GUI session. Captures the app's own rendered content.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/.amp/in/artifacts/flyout-comparison}"
mkdir -p "$OUT"
CONFIGURATION=debug "$ROOT/scripts/build.sh"
for mode in reference shared migration; do
    rm -f "$OUT/$mode-check.txt" "$OUT/$mode-error.txt"
    open -n -W --stderr "$OUT/$mode-error.txt" "$ROOT/.build/GitGaze.app" --args --compare-flyout "$mode" "$OUT"
    if [[ ! -f "$OUT/$mode-check.txt" ]]; then cat "$OUT/$mode-error.txt"; exit 1; fi
    cat "$OUT/$mode-check.txt"
done
