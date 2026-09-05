#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
call_log="$test_tmp/calls"
runtime_dir="$test_tmp/runtime"
mkdir -p "$mock_bin" "$runtime_dir"

cat >"$mock_bin/omarchy-hyprland-monitor-focused-apple" <<'SH'
#!/bin/bash
exit 1
SH

cat >"$mock_bin/omarchy-hyprland-monitor-focused" <<'SH'
#!/bin/bash
printf '%s\n' "${FOCUSED_MONITOR:-eDP-1}"
SH

cat >"$mock_bin/omarchy-hw-display" <<'SH'
#!/bin/bash
printf 'mock_backlight\n'
SH

cat >"$mock_bin/brightnessctl" <<'SH'
#!/bin/bash
printf 'brightnessctl %s\n' "$*" >>"$CALL_LOG"
if [[ $* == *" -m"* ]]; then
  printf 'mock_backlight,backlight,40,40%%\n'
fi
SH

cat >"$mock_bin/ddcutil" <<'SH'
#!/bin/bash
printf 'ddcutil %s\n' "$*" >>"$CALL_LOG"

if [[ $* == *" detect --brief"* ]]; then
  cat <<EOF
Display 1
   I2C bus:             /dev/i2c-${DDC_BUS:-7}
   DRM connector:       card1-${DDC_CONNECTOR:-DP-1}
EOF
elif [[ $* == *" getvcp 10 "* ]]; then
  [[ ${DDC_READ_FAIL:-0} == "1" ]] && exit 1
  printf 'VCP 10 C %s %s\n' "${DDC_CURRENT:-40}" "${DDC_MAXIMUM:-80}"
fi
SH

chmod +x "$mock_bin"/*

# Machine shape, as the kernel presents it. A laptop owns its backlight through
# an eDP connector; an all-in-one wires its built-in panel to DisplayPort and has
# no internal-named connector at all. The all-in-one gets both topologies, alone
# and with a second display attached, so each case runs against the DRM set it
# actually describes.
drm_laptop="$test_tmp/drm-laptop"
drm_aio="$test_tmp/drm-aio"
drm_aio_docked="$test_tmp/drm-aio-docked"
mkdir -p "$drm_laptop/card1-eDP-1" "$drm_laptop/card1-DP-2" \
  "$drm_aio/card1-DP-1" "$drm_aio/card1-DP-2" \
  "$drm_aio_docked/card1-DP-1" "$drm_aio_docked/card1-DP-2"
printf 'connected\n' >"$drm_laptop/card1-eDP-1/status"
printf 'connected\n' >"$drm_laptop/card1-DP-2/status"
printf 'connected\n' >"$drm_aio/card1-DP-1/status"
printf 'disconnected\n' >"$drm_aio/card1-DP-2/status"
printf 'connected\n' >"$drm_aio_docked/card1-DP-1/status"
printf 'connected\n' >"$drm_aio_docked/card1-DP-2/status"

run_brightness() {
  CALL_LOG="$call_log" XDG_RUNTIME_DIR="$runtime_dir" OMARCHY_DRM_PATH="${DRM_PATH:-$drm_laptop}" \
    PATH="$mock_bin:$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-brightness-display" "$@"
}

brightness=$(run_brightness --monitor DP-1)
[[ $brightness == "50" ]] || fail "external brightness is converted to a percentage" "actual: $brightness"
pass "external brightness is converted to a percentage"

(( $(grep -c '^ddcutil --skip-ddc-checks detect --brief$' "$call_log") == 1 )) || fail "DDC bus is detected once"
run_brightness --monitor DP-1 >/dev/null
(( $(grep -c '^ddcutil --skip-ddc-checks detect --brief$' "$call_log") == 1 )) || fail "DDC bus mapping is cached"
pass "DDC bus mapping is cached"

run_brightness --no-osd --monitor DP-1 25%
grep -F 'ddcutil --bus 7 --skip-ddc-checks --noverify setvcp 10 20' "$call_log" >/dev/null || \
  fail "external percentage is converted to the monitor VCP range"
pass "external percentage is converted to the monitor VCP range"

get_count=$(grep -c ' getvcp 10 ' "$call_log")
run_brightness --no-osd --monitor DP-1 30%
(( $(grep -c ' getvcp 10 ' "$call_log") == get_count )) || \
  fail "absolute external brightness reuses the cached VCP range"
grep -F 'ddcutil --bus 7 --skip-ddc-checks --noverify setvcp 10 24' "$call_log" >/dev/null || \
  fail "absolute external brightness skips write verification"
pass "absolute external brightness reuses the cached VCP range"

brightness=$(run_brightness --monitor eDP-1)
[[ $brightness == "40" ]] || fail "internal monitor uses the kernel backlight" "actual: $brightness"
grep -F 'brightnessctl -d mock_backlight -m' "$call_log" >/dev/null || \
  fail "internal monitor queries brightnessctl"
pass "internal monitor uses the kernel backlight"

brightness=$(FOCUSED_MONITOR=DP-1 run_brightness)
[[ $brightness == "50" ]] || fail "brightness follows the focused external monitor" "actual: $brightness"
pass "brightness follows the focused external monitor"

detect_count=$(grep -c ' detect --brief' "$call_log")
if DDC_CONNECTOR=DP-1 run_brightness --monitor DP-2 >/dev/null 2>&1; then
  fail "unsupported external monitor has no brightness backend"
fi
if DDC_CONNECTOR=DP-1 run_brightness --monitor DP-2 >/dev/null 2>&1; then
  fail "cached unsupported external monitor has no brightness backend"
fi
(( $(grep -c ' detect --brief' "$call_log") == detect_count + 1 )) || \
  fail "unsupported external monitor detection is temporarily cached"
pass "unsupported external monitor has no brightness backend"

rm -f "$runtime_dir/omarchy-brightness-display-ddc/DP-1.bus"
detect_count=$(grep -c ' detect --brief' "$call_log")
if DDC_READ_FAIL=1 run_brightness --monitor DP-1 >/dev/null 2>&1; then
  fail "transient DDC read failure is reported"
fi
(( $(grep -c ' detect --brief' "$call_log") == detect_count + 1 )) || \
  fail "transient DDC read failure is not retried immediately"
brightness=$(run_brightness --monitor DP-1)
[[ $brightness == "50" ]] || fail "transient DDC read failure is retried on the next invocation" "actual: $brightness"
(( $(grep -c ' detect --brief' "$call_log") == detect_count + 2 )) || \
  fail "transient DDC read failure does not create a negative cache entry"
pass "transient DDC read failure is retried on the next invocation"

printf '7 80 0\n' >"$runtime_dir/omarchy-brightness-display-ddc/DP-1.bus"
get_count=$(grep -c ' getvcp 10 ' "$call_log")
DDC_MAXIMUM=100 run_brightness --no-osd --monitor DP-1 50%
(( $(grep -c ' getvcp 10 ' "$call_log") == get_count + 1 )) || \
  fail "expired external brightness range is refreshed"
grep -F 'ddcutil --bus 7 --skip-ddc-checks --noverify setvcp 10 50' "$call_log" >/dev/null || \
  fail "expired external brightness range uses the refreshed maximum"
pass "expired external brightness range is refreshed"

rm -f "$runtime_dir/omarchy-brightness-display-ddc/DP-1.bus"
DDC_CURRENT=4 DDC_MAXIMUM=100 run_brightness --no-osd --monitor DP-1 +5%
grep -F 'ddcutil --bus 7 --skip-ddc-checks --noverify setvcp 10 5' "$call_log" >/dev/null || \
  fail "external low brightness writes the one-percent target"
pass "external low brightness uses a one-percent step"

cat >"$mock_bin/hyprctl" <<'SH'
#!/bin/bash
printf '%s\n' '[
  {"name":"DP-1","focused":true,"make":"HPN","model":"OMEN X 25f"},
  {"name":"DP-2","focused":false,"make":"Apple Computer Inc","model":"StudioDisplay"}
]'
SH
chmod +x "$mock_bin/hyprctl"

PATH="$mock_bin:$PATH" "$ROOT/bin/omarchy-hyprland-monitor-focused-apple" DP-2 || \
  fail "named Apple display is detected independently of focus"
if PATH="$mock_bin:$PATH" "$ROOT/bin/omarchy-hyprland-monitor-focused-apple"; then
  fail "focused non-Apple display is not detected as Apple"
fi
pass "named Apple display is detected independently of focus"

# An all-in-one's built-in panel is named DP-1 and answers no DDC display, and
# the machine has no eDP/LVDS/DSI connector that could own the kernel backlight
# instead -- so the backlight is the panel behind that connector.
rm -rf "$runtime_dir/omarchy-brightness-display-ddc"
brightness=$(DRM_PATH="$drm_aio" DDC_CONNECTOR=DP-9 run_brightness --monitor DP-1) ||
  fail "all-in-one panel falls back to the kernel backlight" "the command exited nonzero"
[[ $brightness == "40" ]] || fail "all-in-one panel falls back to the kernel backlight" "actual: $brightness"
pass "a DisplayPort panel with no DDC display uses the kernel backlight"

rm -rf "$runtime_dir/omarchy-brightness-display-ddc"
DRM_PATH="$drm_aio" DDC_CONNECTOR=DP-9 run_brightness --no-osd --monitor DP-1 60%
grep -F 'brightnessctl -d mock_backlight set 60%' "$call_log" >/dev/null ||
  fail "all-in-one panel sets brightness through the kernel backlight"
pass "a DisplayPort panel with no DDC display is adjusted through the kernel backlight"

# The same all-in-one with a real external monitor attached and connected: that
# one answers DDC, so it keeps using it. Only the connector without a DDC display
# falls back.
rm -rf "$runtime_dir/omarchy-brightness-display-ddc"
brightness=$(DRM_PATH="$drm_aio_docked" DDC_CONNECTOR=DP-2 run_brightness --monitor DP-2) ||
  fail "an external monitor on an all-in-one still uses DDC" "the command exited nonzero"
[[ $brightness == "50" ]] || fail "an external monitor on an all-in-one still uses DDC" "actual: $brightness"
pass "an external monitor that answers DDC still uses DDC"

# The built-in panel of that same docked all-in-one still has to reach the
# backlight. A second connected display is not an internal panel, so it cannot
# be what the backlight belongs to.
rm -rf "$runtime_dir/omarchy-brightness-display-ddc"
brightness=$(DRM_PATH="$drm_aio_docked" DDC_CONNECTOR=DP-2 run_brightness --monitor DP-1) ||
  fail "a docked all-in-one still drives its own panel" "the command exited nonzero"
[[ $brightness == "40" ]] || fail "a docked all-in-one still drives its own panel" "actual: $brightness"
pass "an all-in-one panel keeps the kernel backlight with a second display connected"

# A laptop's DDC-less external monitor must keep failing. Falling back would
# move the laptop's own panel while the user is asking for the other one.
rm -rf "$runtime_dir/omarchy-brightness-display-ddc"
if DRM_PATH="$drm_laptop" DDC_CONNECTOR=DP-9 run_brightness --monitor DP-2 >/dev/null 2>&1; then
  fail "a laptop's DDC-less external monitor does not move the internal backlight"
fi
pass "an external monitor on a machine with an internal panel does not fall back"

# A transient DDC read failure is not "no display on this connector", so it must
# not fall back either -- the monitor is there and will answer on the next try.
rm -rf "$runtime_dir/omarchy-brightness-display-ddc"
if DRM_PATH="$drm_aio" DDC_READ_FAIL=1 run_brightness --monitor DP-1 >/dev/null 2>&1; then
  fail "a transient DDC read failure does not fall back to the backlight"
fi
pass "a transient DDC read failure is not treated as a missing DDC display"
