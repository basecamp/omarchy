#!/bin/bash
# Stream cava bar values as whitespace-separated 0-255 decimals, one frame per
# line. Consumed by the bar's `media` widget to drive its FFT visualizer.
#
# Usage: cava-bars.sh [BARS] [FRAMERATE]
# Exits non-zero if cava isn't installed; the widget then hides its visualizer.

set -euo pipefail

BARS="${1:-28}"
FRAMERATE="${2:-60}"

if ! command -v cava >/dev/null 2>&1; then
  exit 1
fi

CFG=$(mktemp --suffix=.cava)
trap 'rm -f "$CFG"' EXIT

cat > "$CFG" <<EOF
[general]
bars = $BARS
framerate = $FRAMERATE

[smoothing]
noise_reduction = 77

[output]
method = raw
raw_target = /dev/stdout
bit_format = 8bit
channels = mono
EOF

# stdbuf -oL line-buffers each stage so cava frames don't get trapped in libc
# buffering. od -w<BARS> emits one frame per line as space-separated decimals,
# which SplitParser on the QML side reads directly.
exec stdbuf -oL cava -p "$CFG" | stdbuf -oL od -An -tu1 -v -w"$BARS"
