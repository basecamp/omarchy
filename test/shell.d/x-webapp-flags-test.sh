#!/bin/bash

# The packaged X webapp is what users launch for x.com. On hybrid
# Intel+NVIDIA laptops with mixed monitor scales, Chromium --app
# reports the eDP scale on HDMI and VA-API points at NVIDIA while
# the GPU process renders on Intel: videos stay on the poster.
# These flags are webapp-only; they must not go in chromium-flags.conf
# (force-device-scale-factor=1 blacks out tabbed Chromium).

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

desktop="$ROOT/applications/X.desktop"
flags="$ROOT/config/chromium-flags.conf"

[[ -f $desktop ]] || fail "packaged X.desktop exists" "missing: $desktop"
pass "packaged X.desktop exists"

grep -E '^Exec=omarchy-launch-webapp https://x.com/' "$desktop" | grep -q -- '--force-device-scale-factor=1' ||
  fail "X webapp forces CSS scale 1" "$(grep '^Exec=' "$desktop")"
pass "X webapp forces CSS scale 1"

grep -E '^Exec=omarchy-launch-webapp https://x.com/' "$desktop" | grep -q -- '--disable-accelerated-video-decode' ||
  fail "X webapp disables broken VAAPI decode" "$(grep '^Exec=' "$desktop")"
pass "X webapp disables broken VAAPI decode"

if [[ -f $flags ]]; then
  grep -q -- 'force-device-scale-factor' "$flags" &&
    fail "global chromium-flags.conf stays free of force-device-scale-factor" "$(cat "$flags")"
  grep -q -- 'disable-accelerated-video-decode' "$flags" &&
    fail "global chromium-flags.conf stays free of disable-accelerated-video-decode" "$(cat "$flags")"
  pass "global chromium-flags.conf stays free of X-only flags"
fi
