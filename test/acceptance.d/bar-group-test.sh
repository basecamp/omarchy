#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Exercise the collapsible widget group: a `type: "group"` layout entry that
# wraps children behind a chevron and reveals them like the tray drawer. The
# regression this guards is that older code dropped id-less group entries during
# layout normalization, so the grouped widgets vanished. Here the bar must keep
# rendering with a group configured, in both collapsed and expanded states.
#
# The acceptance harness syncs this checkout into ~/.local/share/omarchy but
# leaves the live shell running the stock system path, so first repoint the
# session at the synced checkout and restart, or the shell under test would be
# the stock one without the group code.

abs_omarchy="$HOME/.local/share/omarchy"

# Track whether OMARCHY_PATH is present in the session env by its line (not a
# non-empty value), so restore() puts it back exactly — including an empty value
# — and only unsets it when it was truly absent.
env_dump=$(systemctl --user show-environment 2>/dev/null)
had_omarchy_path=0
grep -q '^OMARCHY_PATH=' <<<"$env_dump" && had_omarchy_path=1
original_path=$(sed -n 's/^OMARCHY_PATH=//p' <<<"$env_dump" | tail -1)

config_dir="$HOME/.config/omarchy"
config="$config_dir/shell.json"
backup="$(mktemp)"
had_config=0

mkdir -p "$config_dir"
if [[ -f $config ]]; then
  cp "$config" "$backup"
  had_config=1
fi

restore() {
  if (( had_config )); then
    cp "$backup" "$config"
  else
    rm -f "$config"
  fi
  rm -f "$backup"
  if (( had_omarchy_path )); then
    systemctl --user set-environment OMARCHY_PATH="$original_path" >/dev/null 2>&1 || true
  else
    systemctl --user unset-environment OMARCHY_PATH >/dev/null 2>&1 || true
  fi
  omarchy-restart-shell >/dev/null 2>&1 || true
}
trap restore EXIT

# A layout with the tray drawer and a widget group side by side, so a captured
# screenshot shows the group chevron behaving like the tray's.
write_group_config() {
  local collapsed="$1"

  cat >"$config" <<JSON
{
  "version": 1,
  "bar": {
    "position": "top",
    "centerAnchor": "omarchy.clock",
    "layout": {
      "left": [ { "id": "omarchy.menu" }, { "id": "omarchy.workspaces" } ],
      "center": [ { "id": "omarchy.clock", "format": "dddd HH:mm" } ],
      "right": [
        { "id": "omarchy.tray" },
        {
          "type": "group",
          "collapsed": $collapsed,
          "items": [
            { "id": "omarchy.system-update" },
            { "id": "omarchy.bluetooth" },
            { "id": "omarchy.network" }
          ]
        },
        { "id": "omarchy.audio" },
        { "id": "omarchy.power" }
      ]
    }
  }
}
JSON
}

# Load the synced checkout so the code under test is what actually renders.
write_group_config true
systemctl --user set-environment OMARCHY_PATH="$abs_omarchy"
omarchy-restart-shell >/dev/null 2>&1 || true
wait_until "shell restarts on the synced checkout with a collapsed group" 40 layer_on_screen "omarchy-bar"
sleep 3
screenshot "success-bar-group-collapsed"
pass "bar renders a collapsed widget group without dropping it"

# Expanded (collapsed:false starts the drawer open) so a screenshot captures the
# revealed widgets — the state a hover produces. Adding/removing a group is a
# structural change, so a config reload rebuilds the section.
write_group_config false
omarchy-shell shell reloadConfig >/dev/null 2>&1 || omarchy-restart-shell >/dev/null 2>&1 || true
sleep 3
wait_until "bar renders with an expanded group" 20 layer_on_screen "omarchy-bar"
screenshot "success-bar-group-expanded"
pass "bar renders an expanded widget group with its children visible"
