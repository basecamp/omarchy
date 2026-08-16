#!/bin/bash

# The packaged flags file is what `omarchy refresh` / first-run copy to
# ~/.config/chromium-flags.conf (and what the Brave Origin migration copies).
# WaylandPerSurfaceScale makes Chromium report the scale of a sibling
# output (e.g. eDP at 2) on a scale-1 HDMI window, so sites like x.com
# layout at ~half width and their virtual lists jump on scroll.

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

flags="$ROOT/config/chromium-flags.conf"

[[ -f $flags ]] || fail "packaged chromium-flags.conf exists" "missing: $flags"
pass "packaged chromium-flags.conf exists"

grep -qx -- '--disable-features=WaylandPerSurfaceScale' "$flags" ||
  fail "packaged flags disable WaylandPerSurfaceScale" "$(cat "$flags")"
pass "packaged flags disable WaylandPerSurfaceScale"

grep -qx -- '--ozone-platform=wayland' "$flags" ||
  fail "packaged flags keep ozone wayland" "$(cat "$flags")"
pass "packaged flags keep ozone wayland"

grep -q -- 'WaylandLinuxDrmSyncobj\|force-device-scale-factor\|disable-gpu-compositing' "$flags" &&
  fail "packaged flags stay free of discarded GPU/scale workarounds" "$(cat "$flags")"
pass "packaged flags stay free of discarded GPU/scale workarounds"
