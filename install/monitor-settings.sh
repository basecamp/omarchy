#!/bin/bash

# Install omarchy-monitor-settings for controlling Hyprland monitors
if [ -z "$OMARCHY_BARE" ] && ! command -v omarchy-monitor-settings &>/dev/null; then
  # Install Go if not already installed
  if ! command -v go &>/dev/null; then
    mise use -g go@latest
  fi

  # TODO: Discuss where this should live
  go install github.com/ryanyogan/omarchy-monitor-settings@latest

  sudo mv omarchy-monitor-settings /usr/local/bin/
  sudo chmod +x /usr/local/bin/omarchy-monitor-settings
fi
