#!/bin/bash
# Native-window screenshots. Requires Screen Recording permission for the terminal.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/.amp/in/artifacts"
mkdir -p "$OUT"
osascript -e 'tell application id "app.gitbar.mac" to quit' 2>/dev/null || true
CONFIGURATION=debug "$ROOT/scripts/build.sh"
rm -f "$OUT/review-complete.txt"
open "$ROOT/.build/GitGaze.app" --args --review "$OUT" --show
capture() {
    name="$1"
    marker="$OUT/$name.png.window"
    for ((i=0; i<180; i++)); do
        [ -f "$marker" ] && break
        sleep 0.25
    done
    [ -f "$marker" ] || { echo "Timed out waiting for $name" >&2; exit 1; }
    screencapture -x -o -l "$(cat "$marker")" "$OUT/$name.png"
    rm "$marker"
    echo "Captured $name"
}
for name in dashboard-dark dashboard-light widgets settings people people-settings people-search person-expanded milestones weekly-records menu-dark menu-light dashboard-violet dashboard-coral dashboard-ice dashboard-graphite dashboard-mint dashboard-rose dashboard-amber dashboard-cobalt dashboard-orchid dashboard-lagoon streak-settings years years-full year-settings settings-full custom-settings custom-dark custom-light reminder-picker history-picker celebration celebration-nova celebration-meteors celebration-reduced welcome refreshing celebration-live; do
    capture "$name"
done
for name in widget-flip widget-reorder particles-fireworks particles-nova particles-meteors; do
    marker="$OUT/$name.motion"
    for ((i=0; i<180; i++)); do
        [ -f "$marker" ] && break
        sleep 0.25
    done
    [ -f "$marker" ] || { echo "Timed out waiting for $name" >&2; exit 1; }
    frames="$ROOT/.amp/in/$name-frames"
    mkdir -p "$frames"
    window="$(cat "$marker")"
    start="$(date +%s)"
    touch "$OUT/$name.start"
    count=42
    for ((frame=0; frame<count; frame++)); do
        screencapture -x -o -l "$window" "$frames/$(printf '%03d' "$frame").png"
        sleep 0.03
    done
    elapsed=$(( $(date +%s) - start ))
    awk -v elapsed="$elapsed" -v count="$count" 'BEGIN { print count / (elapsed > 0 ? elapsed : 1) }' > "$frames/fps"
    rm "$marker"
done
capture reopened
for ((i=0; i<180; i++)); do
    [ -f "$OUT/review-complete.txt" ] && break
    sleep 0.25
done
[ -f "$OUT/review-complete.txt" ] || { echo "Review checks did not complete" >&2; exit 1; }
if command -v ffmpeg >/dev/null; then
    for name in widget-flip widget-reorder particles-fireworks particles-nova particles-meteors; do
        frames="$ROOT/.amp/in/$name-frames"
        duration=30
        [[ "$name" == particles-* ]] && duration=5
        ffmpeg -hide_banner -loglevel error -y -framerate "$(cat "$frames/fps")" -i "$frames/%03d.png" \
            -t "$duration" -vf "scale=576:-2:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse" -loop 0 "$OUT/$name.gif"
        ffmpeg -hide_banner -loglevel error -y -i "$OUT/$name.gif" -pix_fmt yuv420p "$OUT/$name.mp4"
        rm -rf "$frames"
    done
fi
echo "Review artifacts: $OUT"
