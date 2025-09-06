#!/bin/bash

set -e

check_boot_hook_exists() {
  local tv_ip="$1"
  local service_name="lgtv-poweron@${tv_ip}.service"
  
  if systemctl is-enabled "$service_name" &>/dev/null; then
    return 0  # Hook exists
  else
    return 1  # Hook does not exist
  fi
}

manage_boot_hook() {
  local tv_ip="$1"
  local tv_name="$2"
  
  if check_boot_hook_exists "$tv_ip"; then
    # Hook exists, ask to remove
    echo "✅ TV is currently set to turn on at boot"
    if gum confirm "Do you want to disable boot startup?"; then
      remove_boot_hook "$tv_ip" "$tv_name"
    else
      echo "ℹ️ Boot startup remains enabled"
    fi
  else
    # Hook does not exist, ask to add
    echo "❌ TV is not set to turn on at boot"
    if gum confirm "Do you want to enable boot startup?"; then
      add_boot_hook "$tv_ip" "$tv_name"
    else
      echo "ℹ️ Boot startup remains disabled"
    fi
  fi
}

add_boot_hook() {
  local tv_ip="$1"
  local tv_name="$2"
  
  echo "🚀 Setting up TV startup on boot..."
  
  # Create systemd service for TV power on at boot
  local service_name="lgtv-poweron@${tv_ip}.service"
  
  sudo tee "/etc/systemd/system/$service_name" <<EOF >/dev/null
[Unit]
Description=Power on LG TV ($tv_name) at boot
After=network.target
Wants=network.target

[Service]
Type=oneshot
User=$USER
ExecStart=pinarchy-cmd-lgtv-wol $tv_ip
RemainAfterExit=yes
TimeoutStartSec=30

[Install]
WantedBy=multi-user.target
EOF

  # Enable the service
  sudo systemctl enable "$service_name"
  
  echo "✅ TV will now turn on automatically at system boot"
  echo "   Service: $service_name"
  
  return 0
}

remove_boot_hook() {
  local tv_ip="$1"
  local tv_name="$2"
  
  echo "🗑️ Removing TV startup on boot..."
  
  local service_name="lgtv-poweron@${tv_ip}.service"
  
  # Disable and remove the service
  sudo systemctl disable "$service_name" &>/dev/null || true
  sudo rm -f "/etc/systemd/system/$service_name"
  
  echo "✅ TV boot startup removed"
  
  return 0
}