#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# The compositor reports at least one monitor
monitors=$(hyprctl -j monitors | jq 'length')
(( monitors >= 1 )) || fail "compositor reports a monitor"
pass "compositor reports a monitor"

# The Omarchy shell is running and responsive
wait_until "omarchy-shell responds to ping" 60 omarchy-shell shell ping

# Core shell plugins are loaded
plugins=$(omarchy-shell shell listPlugins)
for plugin in \
  omarchy.audio omarchy.background omarchy.bar omarchy.bluetooth \
  omarchy.clipboard omarchy.emojis omarchy.menu \
  omarchy.monitor omarchy.network omarchy.notifications omarchy.power \
  omarchy.reminders omarchy.weather \
  omarchy.ultimate-taskbar omarchy.ultimate-start omarchy.ultimate-run \
  omarchy.ultimate-settings omarchy.ultimate-task-switcher omarchy.ultimate-snap-chooser; do
  [[ $plugins == *"$plugin"* ]] || fail "shell plugin is loaded: $plugin" "loaded plugins: $plugins"
  pass "shell plugin is loaded: $plugin"
done

hyprctl plugin list 2>/dev/null | grep -qi hyprbars \
  || fail "hyprbars is loaded for Desktop Mode title bars" "$(hyprctl plugin list 2>/dev/null || true)"
pass "hyprbars is loaded for Desktop Mode title bars"
hypr_pid=$(pgrep -n Hyprland || true)
[[ -n $hypr_pid ]] || fail "Hyprland is running"
if ! grep -E '/usr/lib/hyprland-plugins/hyprbars\.so|/default/hypr/plugins/hyprbars/hyprbars\.so' /proc/$hypr_pid/maps >/dev/null; then
  fail "hyprbars is mapped from a tree or /usr/lib plugin" "$(awk '{print $6}' /proc/$hypr_pid/maps | sort -u | grep hypr || true)"
fi
pass "hyprbars is mapped from a tree or /usr/lib plugin"
if grep -Fq '/var/cache/hyprpm/' /proc/$hypr_pid/maps; then
  fail "hyprbars must not be mapped from the hyprpm cache" "$(awk '{print $6}' /proc/$hypr_pid/maps | sort -u | grep hypr || true)"
fi
hyprctl plugin list 2>/dev/null | grep -qi omarchy-minimize \
  || fail "omarchy-minimize is loaded for native hide" "$(hyprctl plugin list 2>/dev/null || true)"
pass "omarchy-minimize is loaded for native hide"
if ! grep -E '/usr/lib/hyprland-plugins/omarchy-minimize\.so|/default/hypr/plugins/omarchy-minimize/omarchy-minimize\.so' /proc/$hypr_pid/maps >/dev/null; then
  fail "omarchy-minimize is mapped from a tree or /usr/lib plugin"
fi
pass "omarchy-minimize is mapped from a tree or /usr/lib plugin"
layer_absent "omarchy-window-chrome" || fail "overlay caption layer is gone"
pass "overlay caption layer is gone"

# Desktop Mode shows the taskbar; Power User Mode keeps the heritage top bar.
wait_until "shell chrome layer is mapped" 30 chrome_layer_namespace
chrome_ns=$(chrome_layer_namespace)
wait_until "bar layer is on screen" 30 layer_on_screen "$chrome_ns"
wait_until "background layer is on screen" 30 layer_on_screen "omarchy-background"

# Hiding parks the bar off-screen without unmapping its layer surface, and
# revealing brings that same surface back on-screen.
restore_bar_visibility() {
  omarchy-toggle-bar off >/dev/null 2>&1 || true
}
trap restore_bar_visibility EXIT

omarchy-toggle-bar on
wait_until "hidden bar layer stays mapped" 15 layer_present "$chrome_ns"
wait_until "hidden bar layer parks off screen" 15 layer_off_screen "$chrome_ns"
screenshot "success-bar-hidden"

omarchy-toggle-bar off
wait_until "revealed bar layer returns on screen" 15 layer_on_screen "$chrome_ns"
screenshot "success-bar-revealed"
trap - EXIT

# Audio stack is up
wait_until "pipewire is running" 30 wpctl status

# Root filesystem is btrfs as installed
[[ $(findmnt -no FSTYPE /) == "btrfs" ]] || fail "root filesystem is btrfs"
pass "root filesystem is btrfs"

# Omarchy reports its version
omarchy-version >/dev/null || fail "omarchy-version works"
pass "omarchy-version works"

# No failed units, system or user. OMARCHY_ACCEPTANCE_IGNORE_UNITS can hold a
# regex of units to overlook (useful on dev machines; a fresh VM should be clean).
failed_units() {
  systemctl "$@" --failed --no-legend --plain | awk '{print $1}' |
    grep -Ev "${OMARCHY_ACCEPTANCE_IGNORE_UNITS:-^$}" || true
}

failed_system=$(failed_units --system)
if [[ -n $failed_system ]]; then
  fail "no failed system units" "failed units: $failed_system"
fi
pass "no failed system units"

failed_user=$(failed_units --user)
if [[ -n $failed_user ]]; then
  fail "no failed user units" "failed units: $failed_user"
fi
pass "no failed user units"

screenshot "success-desktop"
