#!/bin/bash

# Toggles the window gaps on the active workspace between no gaps and the default 10/5/2.

workspace_id=$(hyprctl activeworkspace -j | jq -r .id)
gaps=$(hyprctl workspacerules -j | jq -r ".[] | select(.workspaceString==\"$workspace_id\") | .gapsOut[0] // 0")

if [[ $gaps == "0" ]]; then
  hyprctl keyword "workspace $workspace_id, gapsout:10, gapsin:5, bordersize:2"
else \
  hyprctl keyword "workspace $workspace_id, gapsout:0, gapsin:0, bordersize:0"
fi
