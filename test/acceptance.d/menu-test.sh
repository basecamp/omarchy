#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

CONFIG_FILE="$HOME/.config/omarchy/shell.json"
DEFAULTS_FILE="$OMARCHY_PATH/config/omarchy/shell.json"
config_backup=$(mktemp)
config_existed=0

if [[ -f $CONFIG_FILE ]]; then
  cp "$CONFIG_FILE" "$config_backup"
  config_existed=1
fi

restore_bar_config() {
  omarchy-shell shell hide omarchy.menu >/dev/null 2>&1 || true

  if ((config_existed)); then
    mkdir -p "$(dirname "$CONFIG_FILE")"
    cp "$config_backup" "$CONFIG_FILE"
  else
    rm -f "$CONFIG_FILE"
  fi

  omarchy-shell shell reloadConfig >/dev/null 2>&1 || true
  rm -f "$config_backup"
}

trap restore_bar_config EXIT

bar_is_vertical() {
  local width height

  read -r width height < <(hyprctl -j layers | jq -r '
    [.. | objects | select(.namespace? == "omarchy-bar")][0]
    | [.w, .h] | @tsv
  ')

  [[ $width =~ ^[0-9]+$ && $height =~ ^[0-9]+$ ]] && ((width < height))
}

bar_is_horizontal() {
  local width height

  read -r width height < <(hyprctl -j layers | jq -r '
    [.. | objects | select(.namespace? == "omarchy-bar")][0]
    | [.w, .h] | @tsv
  ')

  [[ $width =~ ^[0-9]+$ && $height =~ ^[0-9]+$ ]] && ((width > height))
}

bar_position_is() {
  local expected="$1"

  [[ $(jq -r '.bar.position // "top"' "$CONFIG_FILE") == $expected ]]
}

source_file=$DEFAULTS_FILE
((config_existed)) && source_file=$CONFIG_FILE
original_position=$(jq -r '.bar.position // "top"' "$source_file")

omarchy-shell shell summon omarchy.menu '{"menu":"root"}' >/dev/null
wait_until "root menu opens" 15 layer_present "omarchy-menu"
wait_until "root menu content is visible" 15 screen_contains "Apps"
screenshot "success-menu-01-root"

wtype -k Down -k Down -k Down
sleep 1
screenshot "success-menu-02-style-selected"
wtype -k Return

wait_until "style submenu is visible" 15 screen_contains "Theme"
screenshot "success-menu-03-style-submenu"

wtype -k Down -k Down -k Down -k Return
sleep 1
screenshot "success-menu-04-menu-bar-submenu"

wtype -k Return
sleep 1
screenshot "success-menu-05-position-submenu"

wtype -k Down -k Down -k Return
wait_until "menu bar position changes to left" 20 bar_position_is "left"
wait_until "menu bar becomes vertical" 20 bar_is_vertical
wait_until "menu closes after selecting a position" 15 layer_absent "omarchy-menu"
screenshot "success-menu-06-bar-left"

if ((config_existed)); then
  cp "$config_backup" "$CONFIG_FILE"
else
  rm -f "$CONFIG_FILE"
fi
omarchy-shell shell reloadConfig >/dev/null

if [[ $original_position == "left" || $original_position == "right" ]]; then
  wait_until "menu bar restores its original vertical position" 20 bar_is_vertical
else
  wait_until "menu bar restores its original horizontal position" 20 bar_is_horizontal
fi
screenshot "success-menu-07-bar-restored"

trap - EXIT
restore_bar_config
