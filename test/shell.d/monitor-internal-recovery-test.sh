#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

fake_home="$test_tmp/home"
fake_bin="$test_tmp/bin"
drm_path="$test_tmp/drm"
monitors_file="$test_tmp/monitors.json"
calls="$test_tmp/hyprctl-calls"
toggles_dir="$fake_home/.local/state/omarchy/toggles/hypr"

mkdir -p "$fake_bin" "$toggles_dir"

for command in \
  omarchy-hw-external-monitors \
  omarchy-hyprland-monitor-external-active \
  omarchy-hyprland-monitor-laptop \
  omarchy-hyprland-toggle \
  omarchy-hyprland-toggle-enabled; do
  ln -s "$ROOT/bin/$command" "$fake_bin/$command"
done

cat >"$fake_bin/hyprctl" <<'SH'
#!/bin/bash

case "${1:-}" in
monitors)
  cat "$OMARCHY_TEST_MONITORS_FILE"
  ;;
reload | dispatch | eval)
  printf '%s\n' "$*" >>"$OMARCHY_TEST_HYPRCTL_CALLS"
  ;;
esac
SH
chmod +x "$fake_bin/hyprctl"

write_connectors() {
  local index=1 external_state

  rm -rf "$drm_path"
  mkdir -p "$drm_path/card0-eDP-1"
  printf 'connected\n' >"$drm_path/card0-eDP-1/status"

  for external_state in "$@"; do
    mkdir -p "$drm_path/card0-HDMI-A-$index"
    printf '%s\n' "$external_state" >"$drm_path/card0-HDMI-A-$index/status"
    index=$((index + 1))
  done
}

write_monitors() {
  printf '%s' "$1" >"$monitors_file"
}

make_toggle() {
  printf 'test\n' >"$toggles_dir/$1.lua"
}

run_recovery() {
  HOME="$fake_home" \
  PATH="$fake_bin:$PATH" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_DRM_PATH="$drm_path" \
  OMARCHY_TEST_MONITORS_FILE="$monitors_file" \
  OMARCHY_TEST_HYPRCTL_CALLS="$calls" \
    "$ROOT/bin/$1" recover
}

assert_recovered() {
  local toggle="$1" description="$2"

  [[ ! -f $toggles_dir/$toggle.lua ]] || fail "$description" "toggle was not removed"
  grep -Fx 'reload' "$calls" >/dev/null || fail "$description" "Hyprland was not reloaded"
  pass "$description"
}

active_external='[{"name":"eDP-1","disabled":true},{"name":"HDMI-A-1","disabled":false}]'
no_active_external='[{"name":"eDP-1","disabled":true}]'

# The kernel has processed the unplug, but Hyprland can retain the removed HDMI
# output as active long enough for every event-driven retry to make the same
# wrong decision. Physical disconnection must win in this disagreement.
write_connectors disconnected
write_monitors "$active_external"
: >"$calls"
make_toggle internal-monitor-disable
run_recovery omarchy-hyprland-monitor-internal
assert_recovered internal-monitor-disable \
  "a physically disconnected external monitor recovers the laptop despite stale Hyprland state"
grep -F 'dispatch hl.dsp.dpms({ action = "enable" })' "$calls" >/dev/null ||
  fail "internal monitor recovery wakes the display after clearing its toggle"
pass "internal monitor recovery wakes the display after clearing its toggle"

: >"$calls"
make_toggle internal-monitor-mirror
run_recovery omarchy-hyprland-monitor-internal-mirror
assert_recovered internal-monitor-mirror \
  "a physically disconnected external monitor clears stale mirroring state"

# Do not mistake removal of one display for undocking when another usable
# external display remains.
write_connectors connected
write_monitors "$active_external"
: >"$calls"
make_toggle internal-monitor-disable
make_toggle internal-monitor-mirror
run_recovery omarchy-hyprland-monitor-internal
run_recovery omarchy-hyprland-monitor-internal-mirror
[[ -f $toggles_dir/internal-monitor-disable.lua ]] ||
  fail "an active connected external monitor preserves the laptop display toggle"
[[ -f $toggles_dir/internal-monitor-mirror.lua ]] ||
  fail "an active connected external monitor preserves the mirror toggle"
[[ ! -s $calls ]] || fail "healthy external monitor state does not reconfigure displays" "$(<"$calls")"
pass "an active connected external monitor preserves intentional laptop display state"

# Unplugging one of two externals is not an undock. The connector scan must keep
# looking past the one that went away rather than answer from the first it reads.
write_connectors disconnected connected
write_monitors "$active_external"
: >"$calls"
make_toggle internal-monitor-disable
make_toggle internal-monitor-mirror
run_recovery omarchy-hyprland-monitor-internal
run_recovery omarchy-hyprland-monitor-internal-mirror
[[ -f $toggles_dir/internal-monitor-disable.lua ]] ||
  fail "a remaining external monitor preserves the laptop display toggle"
[[ -f $toggles_dir/internal-monitor-mirror.lua ]] ||
  fail "a remaining external monitor preserves the mirror toggle"
[[ ! -s $calls ]] || fail "unplugging one of two externals does not reconfigure displays" "$(<"$calls")"
pass "unplugging one of two external monitors keeps the laptop display disabled"

# A connected but inactive external is not usable. Keep the compositor-side
# half of the old recovery behavior as well as the new hardware-side fallback.
write_monitors "$no_active_external"
: >"$calls"
run_recovery omarchy-hyprland-monitor-internal
assert_recovered internal-monitor-disable \
  "an inactive external monitor still recovers the laptop display"

# Polling recovery runs frequently. It must not wake a panel blanked by the lock
# screen when there is no disable toggle to clear.
write_connectors disconnected
write_monitors "$active_external"
rm -f "$toggles_dir/internal-monitor-mirror.lua"
: >"$calls"
run_recovery omarchy-hyprland-monitor-internal
[[ ! -s $calls ]] || fail "recovery without a toggle does not wake the display" "$(<"$calls")"
pass "recovery without a toggle does not wake the display"
