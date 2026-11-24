#!/usr/bin/env bash
# Turns a screen recording (.mov from ⌘⇧5) into a README-sized GIF.
#   tools/make-gif.sh recording.mov docs/demo-slack.gif [width] [start] [end]
# width defaults to 800px; start/end (seconds) trim the clip.
set -euo pipefail
IN="${1:?usage: make-gif.sh in.mov out.gif [width] [start] [end]}"
OUT="${2:?usage: make-gif.sh in.mov out.gif [width] [start] [end]}"
WIDTH="${3:-800}"
TRIM=()
[ -n "${4:-}" ] && TRIM+=(-ss "$4")
[ -n "${5:-}" ] && TRIM+=(-to "$5")
FILTERS="fps=15,scale=${WIDTH}:-1:flags=lanczos"
PALETTE="$(mktemp -t palette).png"
trap 'rm -f "$PALETTE"' EXIT

# Two passes: build a palette from the clip, then dither against it —
# much sharper text than ffmpeg's default 256-color GIF.
ffmpeg -v error "${TRIM[@]}" -i "$IN" -vf "${FILTERS},palettegen=stats_mode=diff" -y "$PALETTE"
ffmpeg -v error "${TRIM[@]}" -i "$IN" -i "$PALETTE" \
    -lavfi "${FILTERS} [x]; [x][1:v] paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" -y "$OUT"
echo "✓ $OUT ($(du -h "$OUT" | cut -f1))"
[ "$(stat -f%z "$OUT")" -gt 10000000 ] && echo "  ⚠ over 10 MB — GitHub won't inline it; try a smaller width or shorter clip"
true
