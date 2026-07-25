#!/bin/bash

# omarchy:summary=Toggle the layout on the current active workspace between dwindle and scrolling

ACTIVE_WORKSPACE=$(hyprctl activeworkspace -j | jq -r '.id')
[[ $ACTIVE_WORKSPACE =~ ^-?[0-9]+$ ]] || exit 1
CURRENT_LAYOUT=$(hyprctl activeworkspace -j | jq -r '.tiledLayout')
LAYOUTS_DIR="$HOME/.local/state/omarchy/workspace-layouts"
LAYOUT_FILE="$LAYOUTS_DIR/$ACTIVE_WORKSPACE.lua"

case "$CURRENT_LAYOUT" in
  dwindle) NEW_LAYOUT=scrolling ;;
  *) NEW_LAYOUT=dwindle ;;
esac

mkdir -p "$LAYOUTS_DIR"
printf 'hl.workspace_rule({ workspace = "%s", layout = "%s" })\n' "$ACTIVE_WORKSPACE" "$NEW_LAYOUT" >"$LAYOUT_FILE"

hyprctl eval "hl.workspace_rule({ workspace = \"$ACTIVE_WORKSPACE\", layout = \"$NEW_LAYOUT\" })" >/dev/null 2>&1 || \
  hyprctl keyword workspace "$ACTIVE_WORKSPACE, layout:$NEW_LAYOUT"
omarchy-notification-send -g 󱂬 "Workspace layout set to $NEW_LAYOUT"
