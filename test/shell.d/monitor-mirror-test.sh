#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
home_dir="$test_tmp/home"
state_dir="$home_dir/.local/state/omarchy/toggles/hypr"
mirror_flag="$state_dir/internal-monitor-mirror.lua"

mkdir -p "$stub_bin" "$state_dir"

# The monitor list is whatever the case under test exports, so one stub covers
# a laptop alone, a laptop plus one external, and a laptop plus several.
cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash

if [[ $1 == "monitors" && $2 == "-j" ]]; then
  printf '%s' "${OMARCHY_TEST_MONITORS:-[]}"
elif [[ $1 == "reload" ]]; then
  printf 'reload\n' >>"$OMARCHY_TEST_LOG"
else
  exit 1
fi
SH

cat >"$stub_bin/omarchy-hyprland-monitor-laptop" <<'SH'
#!/bin/bash
printf '%s\n' "${OMARCHY_TEST_INTERNAL:-eDP-1}"
SH

cat >"$stub_bin/omarchy-hyprland-toggle" <<'SH'
#!/bin/bash
[[ $2 == "off" ]] && rm -f "$HOME/.local/state/omarchy/toggles/hypr/$1.lua"
exit 0
SH

cat >"$stub_bin/omarchy-hyprland-toggle-disabled" <<'SH'
#!/bin/bash
[[ ! -f "$HOME/.local/state/omarchy/toggles/hypr/$1.lua" ]]
SH

cat >"$stub_bin/omarchy-hyprland-toggle-enabled" <<'SH'
#!/bin/bash
[[ -f "$HOME/.local/state/omarchy/toggles/hypr/$1.lua" ]]
SH

cat >"$stub_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf 'notify %s\n' "${*: -1}" >>"$OMARCHY_TEST_LOG"
SH

chmod +x "$stub_bin"/*

mirror() {
  HOME="$home_dir" \
  PATH="$stub_bin:$PATH" \
  OMARCHY_TEST_LOG="$test_tmp/log" \
    bash "$ROOT/bin/omarchy-hyprland-monitor-internal-mirror" "$@"
}

laptop_and() {
  local extra="$1"
  printf '[{"name":"eDP-1","x":0,"y":1000,"transform":0}%s]' "$extra"
}

# --- mirroring covers every external, not just the first ---

rm -f "$mirror_flag" "$test_tmp/log"
OMARCHY_TEST_MONITORS=$(laptop_and ',{"name":"DP-7","x":0,"y":0,"transform":0}') mirror on

grep -Fq 'output = "DP-7"' "$mirror_flag"
grep -Fq 'mirror = "eDP-1"' "$mirror_flag"
[[ $(grep -c 'hl.monitor' "$mirror_flag") == 1 ]]
pass "a single external mirrors the laptop panel"

rm -f "$mirror_flag" "$test_tmp/log"
OMARCHY_TEST_MONITORS=$(laptop_and ',{"name":"DP-7","x":0,"y":0,"transform":0},{"name":"HDMI-A-1","x":2560,"y":0,"transform":0}') mirror on

[[ $(grep -c 'hl.monitor' "$mirror_flag") == 2 ]]
grep -Fq 'output = "DP-7"' "$mirror_flag"
grep -Fq 'output = "HDMI-A-1"' "$mirror_flag"
pass "a second external mirrors too rather than staying extended"

# Each rule names the laptop as the source, so no external mirrors another
# external and none is left showing its own content.
[[ $(grep -c 'mirror = "eDP-1"' "$mirror_flag") == 2 ]]
pass "the laptop panel is the source for every mirror"

# --- the source's position is pinned onto every mirror ---

[[ $(grep -c 'position = "0x1000"' "$mirror_flag") == 2 ]]
pass "every mirror is pinned to the laptop panel's position"

# --- rotation is carried per display, not copied from the first ---

rm -f "$mirror_flag" "$test_tmp/log"
OMARCHY_TEST_MONITORS=$(laptop_and ',{"name":"DP-7","x":0,"y":0,"transform":0},{"name":"HDMI-A-1","x":2560,"y":0,"transform":1}') mirror on

grep -Eq 'output = "DP-7".*mirror = "eDP-1" \}' "$mirror_flag"
grep -Fq 'transform = 1' "$mirror_flag"
[[ $(grep -c 'transform =' "$mirror_flag") == 1 ]]
pass "each external keeps its own rotation"

# --- nothing to mirror to ---

rm -f "$mirror_flag" "$test_tmp/log"
OMARCHY_TEST_MONITORS=$(laptop_and '') mirror on || true

[[ ! -f $mirror_flag ]]
grep -Fq 'No external monitors found for mirror' "$test_tmp/log"
pass "a laptop with no external refuses rather than writing an empty rule set"

# --- turning it back off ---

rm -f "$test_tmp/log"
OMARCHY_TEST_MONITORS=$(laptop_and ',{"name":"DP-7","x":0,"y":0,"transform":0}') mirror on
OMARCHY_TEST_MONITORS=$(laptop_and ',{"name":"DP-7","x":0,"y":0,"transform":0}') mirror off

[[ ! -f $mirror_flag ]]
pass "extending again clears every mirror rule at once"
