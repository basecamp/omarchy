#!/bin/bash

# Install omarchy-monitor-settings for controlling Hyprland monitors
if [ -z "$OMARCHY_BARE" ] && ! command -v omarchy-monitor-settings &>/dev/null; then
  # Install Go if not already installed
  if ! command -v go &>/dev/null; then
    yay -S --noconfirm --needed go
  fi

  # Clone and build the monitor settings application
  git clone https://github.com/ryanyogan/omarchy-monitor-settings.git /tmp/omarchy-monitor-settings
  cd /tmp/omarchy-monitor-settings
  export CGO_ENABLED=0
  export GOOS=linux
  go build -ldflags "-s -w" -o omarchy-monitor-settings
  sudo mv omarchy-monitor-settings /usr/local/bin/
  sudo chmod +x /usr/local/bin/omarchy-monitor-settings
  cd -
  rm -rf /tmp/omarchy-monitor-settings
fi

