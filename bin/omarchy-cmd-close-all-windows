#!/bin/bash

# Close all open windows
hyprctl clients -j | \
  jq -r ".[].address" | \
  xargs -I{} hyprctl dispatch closewindow address:{}

# Move to first workspace
hyprctl dispatch workspace 1
