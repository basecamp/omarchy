#!/bin/bash

set -e

check_shutdown_hook_exists() {
  local tv_ip="$1"
  local service_name="lgtv-poweroff@${tv_ip}.service"
  
  if systemctl is-enabled "$service_name" &>/dev/null; then
    return 0  # Hook exists
  else
    return 1  # Hook does not exist
  fi
}

manage_shutdown_hook() {
  local tv_ip="$1"
  local tv_name="$2"
  
  if check_shutdown_hook_exists "$tv_ip"; then
    # Hook exists, ask to remove
    echo "✅ TV is currently set to turn off on shutdown"
    if gum confirm "Do you want to disable shutdown poweroff?"; then
      remove_shutdown_hook "$tv_ip" "$tv_name"
    else
      echo "ℹ️ Shutdown poweroff remains enabled"
    fi
  else
    # Hook does not exist, ask to add
    echo "❌ TV is not set to turn off on shutdown"
    if gum confirm "Do you want to enable shutdown poweroff?"; then
      add_shutdown_hook "$tv_ip" "$tv_name"
    else
      echo "ℹ️ Shutdown poweroff remains disabled"
    fi
  fi
}

add_shutdown_hook() {
  local tv_ip="$1"
  local tv_name="$2"
  
  echo "⏹️ Setting up TV poweroff on shutdown..."
  
  # Create systemd service for TV power off on shutdown
  local service_name="lgtv-poweroff@${tv_ip}.service"
  
  sudo tee "/etc/systemd/system/$service_name" <<EOF >/dev/null
[Unit]
Description=Power off LG TV ($tv_name) on shutdown
DefaultDependencies=no
Before=shutdown.target reboot.target halt.target
Requires=network.target

[Service]
Type=oneshot
RemainAfterExit=true
User=$USER
ExecStart=/bin/true
ExecStop=pinarchy-cmd-lgtv-shutdown $tv_ip
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF

  # Enable the service
  sudo systemctl enable "$service_name"
  
  echo "✅ TV will now turn off automatically on system shutdown"
  echo "   Service: $service_name"
  
  return 0
}

remove_shutdown_hook() {
  local tv_ip="$1"
  local tv_name="$2"
  
  echo "🗑️ Removing TV poweroff on shutdown..."
  
  local service_name="lgtv-poweroff@${tv_ip}.service"
  
  # Disable and remove the service
  sudo systemctl disable "$service_name" &>/dev/null || true
  sudo rm -f "/etc/systemd/system/$service_name"
  
  echo "✅ TV shutdown poweroff removed"
  
  return 0
}