#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

WEATHER_FILE="$HOME/.local/state/omarchy/settings/weather.json"
weather_backup=$(mktemp)
weather_existed=0

if [[ -f $WEATHER_FILE ]]; then
  cp "$WEATHER_FILE" "$weather_backup"
  weather_existed=1
fi

hide_panels() {
  local plugin

  for plugin in omarchy.weather omarchy.bluetooth omarchy.network omarchy.audio omarchy.monitor omarchy.power; do
    omarchy-shell shell hide "$plugin" >/dev/null 2>&1 || true
  done
}

restore_weather() {
  hide_panels
  close_windows 'org\.omarchy\.screensaver'

  if ((weather_existed)); then
    mkdir -p "$(dirname "$WEATHER_FILE")"
    cp "$weather_backup" "$WEATHER_FILE"
  else
    rm -f "$WEATHER_FILE"
  fi

  rm -f "$weather_backup"
}

trap restore_weather EXIT

open_and_capture_panel() {
  local name="$1" plugin="$2"

  omarchy-shell shell summon "$plugin" >/dev/null
  wait_until "$name panel opens" 15 layer_present "omarchy-keyboard-panel"
  sleep 1
  screenshot "success-panel-$name"

  omarchy-shell shell hide "$plugin" >/dev/null
  wait_until "$name panel closes" 15 layer_absent "omarchy-keyboard-panel"
}

screen_contains_upscaled() {
  local text="$1"
  local work snapshot status=1

  work=$(mktemp -d)
  snapshot="$work/screen.png"

  if timeout 10 grim "$snapshot" 2>/dev/null &&
    magick "$snapshot" -crop 2x2@ +repage -resize 400% -colorspace Gray -auto-level "$work/tile-%d.png" 2>/dev/null; then
    if for tile in "$work"/tile-*.png; do
      tesseract "$tile" stdout --psm 11 2>/dev/null
    done | grep -Fi -- "$text" >/dev/null; then
      status=0
    fi
  fi

  rm -rf "$work"
  return "$status"
}

open_and_capture_power_panel() {
  omarchy-shell shell summon omarchy.power >/dev/null
  wait_until "power panel opens" 15 layer_present "omarchy-keyboard-panel"
  wait_until "available power profiles are visible" 15 screen_contains_upscaled "AVAILABLE POWER PROFILES"

  if upower -e | grep '/battery_' >/dev/null; then
    wait_until "power battery details are visible" 15 screen_contains_upscaled "Battery"
  else
    if screen_contains_upscaled "Battery"; then
      fail "power panel hides battery details without battery hardware"
    fi
    pass "power panel hides battery details without battery hardware"
  fi

  sleep 1
  screenshot "success-panel-power"
  omarchy-shell shell hide omarchy.power >/dev/null
  wait_until "power panel closes" 15 layer_absent "omarchy-keyboard-panel"
}

verify_power_hidden_over_screensaver() {
  omarchy-launch-screensaver force
  wait_until "screensaver opens for power suppression" 15 window_present 'org\.omarchy\.screensaver'

  omarchy-shell shell summon omarchy.power >/dev/null
  sleep 1
  layer_absent "omarchy-keyboard-panel" || fail "power panel stays hidden over the screensaver"
  pass "power panel stays hidden over the screensaver"
  screenshot "success-panel-power-screensaver-hidden"

  close_windows 'org\.omarchy\.screensaver'
  wait_until "screensaver closes after power suppression" 15 window_absent 'org\.omarchy\.screensaver'
}

# Give weather deterministic coordinates so this test exercises the real
# Open-Meteo forecast instead of IP geolocation through wttr.in.
omarchy-weather-location --set "San Francisco" "37.7749,-122.4194"
omarchy-shell shell summon omarchy.weather >/dev/null
wait_until "weather panel opens" 15 layer_present "omarchy-keyboard-panel"
wait_until "weather location is visible" 30 screen_contains "SAN FRANCISCO"
wait_until "weather details are visible" 30 screen_contains "WIND"
screenshot "success-panel-weather"
omarchy-shell shell hide omarchy.weather >/dev/null
wait_until "weather panel closes" 15 layer_absent "omarchy-keyboard-panel"

status=0
panels='bluetooth|omarchy.bluetooth
network|omarchy.network
audio|omarchy.audio
monitor|omarchy.monitor'

while IFS='|' read -r name plugin; do
  if ! (trap - EXIT; open_and_capture_panel "$name" "$plugin"); then
    status=1
    hide_panels
    wait_until "$name failed panel is dismissed" 15 layer_absent "omarchy-keyboard-panel"
  fi
done <<<"$panels"

# The profile picker is useful on every machine. Battery-less systems render
# the supported profiles without the battery-specific hero and statistics.
if ! (trap - EXIT; open_and_capture_power_panel); then
  status=1
  hide_panels
  wait_until "power failed panel is dismissed" 15 layer_absent "omarchy-keyboard-panel"
fi

if ! (trap - EXIT; verify_power_hidden_over_screensaver); then
  status=1
  hide_panels
  close_windows 'org\.omarchy\.screensaver'
  wait_until "power suppression failure is dismissed" 15 layer_absent "omarchy-keyboard-panel"
  wait_until "screensaver suppression failure is dismissed" 15 window_absent 'org\.omarchy\.screensaver'
fi

# The common panel keyboard contract uses Tab to move to the next bar panel.
omarchy-shell shell summon omarchy.bluetooth >/dev/null
wait_until "panel keyboard navigation starts on bluetooth" 15 screen_contains "Bluetooth"
screenshot "success-panel-navigation-01-bluetooth"
wtype -k Tab
sleep 2
wait_until "Tab keeps a shell panel open" 15 layer_present "omarchy-keyboard-panel"
screenshot "success-panel-navigation-02-next"
hide_panels
wait_until "keyboard-navigated panel closes" 15 layer_absent "omarchy-keyboard-panel"

# Reopening during the fade keeps the layer surface mapped. Verify the focus
# prime reacquires compositor keyboard focus instead of relying on map-time
# OnDemand behavior, which would leave Escape in the previously focused app.
omarchy-shell shell summon omarchy.bluetooth >/dev/null
wait_until "focus-prime panel opens" 15 layer_present "omarchy-keyboard-panel"
if (( $(hyprctl -j monitors | jq length) == 1 )); then
  layer_absent "omarchy-keyboard-panel-dismiss" || fail "single-monitor panel has no dismissal twin"
  pass "single-monitor panel has no dismissal twin"
fi
omarchy-shell shell hide omarchy.bluetooth >/dev/null
omarchy-shell shell summon omarchy.bluetooth >/dev/null
wait_until "focus-prime panel reopens" 15 layer_present "omarchy-keyboard-panel"
sleep 1
screenshot "success-panel-focus-prime-reopened"
wtype -k Escape
wait_until "Escape closes a panel reopened during fade" 15 layer_absent "omarchy-keyboard-panel"

trap - EXIT
restore_weather
exit $status
