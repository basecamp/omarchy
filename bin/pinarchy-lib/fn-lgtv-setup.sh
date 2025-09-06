#!/bin/bash

set -e


test_connection() {
  local ip="$1"
  if [ -z "$ip" ]; then
    echo "❌ IP address required for connection test"
    return 1
  fi
  
  local result=$(bscpylgtvcommand -o "$ip" get_hello_info true -p "$HOME/.config/lgtv/bscpylgtv.sqlite" 2>/dev/null)
  
  if [ -z "$result" ]; then
    echo "❌ No response from TV"
    return 1
  fi

  # Parse JSON response
  local os_release=$(echo "$result" | jq -r '.deviceOSReleaseVersion // empty' 2>/dev/null)
  local os_version=$(echo "$result" | jq -r '.deviceOSVersion // empty' 2>/dev/null)
  
  if [ -z "$os_release" ] || [ -z "$os_version" ]; then
    echo "❌ Invalid TV response"
    return 1
  fi
  
  # Show user the TV info
  echo "✅ TV Connected Successfully!"
  echo "   OS Release: $os_release"
  echo "   OS Version: $os_version"
  
  return 0
}

add_tv() {
  # Step 1: Make sure config file exists in ~/.config/lgtv/config.json
  mkdir -p "$HOME/.config/lgtv"
  local config_file="$HOME/.config/lgtv/config.json"
  if [ ! -f "$config_file" ]; then
    echo '{"tvs": []}' > "$config_file"
    echo "✅ Created config file: $config_file"
  fi
  
  echo
  
  # Step 2: Ask for TV IP address
  TV_IP=$(gum input --placeholder "Enter TV IP address (e.g., 192.168.1.100)")
  
  if [ -z "$TV_IP" ]; then
    echo "❌ IP address is required"
    return 1
  fi
  
  echo "📡 Using IP: $TV_IP"
  echo
  
  # Step 3: Connection test
  echo "🔌 Testing connection to TV..."
  if ! test_connection "$TV_IP"; then
    echo "❌ Failed to connect to TV. Please check the IP address and try again."
    return 1
  fi
  echo
  
  # Step 4: Ask for TV Name
  TV_NAME=$(gum input --placeholder "Enter TV name (e.g., Living Room TV)")
  
  if [ -z "$TV_NAME" ]; then
    echo "❌ TV name is required"
    return 1
  fi
  
  echo "📺 TV Name: $TV_NAME"
  echo
  
  # Step 5: Get MAC address
  echo "🔍 Getting MAC address..."
  ping -c 1 -W 1 "$TV_IP" >/dev/null 2>&1 || true
  
  # Try to get MAC using modern ip command
  MAC_ADDRESS=$(ip neigh show "$TV_IP" 2>/dev/null | grep -o '[0-9a-f]\{2\}:[0-9a-f]\{2\}:[0-9a-f]\{2\}:[0-9a-f]\{2\}:[0-9a-f]\{2\}:[0-9a-f]\{2\}' | head -1)
  
  if [ -z "$MAC_ADDRESS" ]; then
    echo "❌ Could not auto-detect MAC address."
    echo "💡 Find MAC address in TV Settings → Network → Advanced Settings"
    MAC_ADDRESS=$(gum input --placeholder "Enter MAC address (aa:bb:cc:dd:ee:ff)" --prompt "MAC Address: ")
    
    if [ -z "$MAC_ADDRESS" ]; then
      echo "❌ MAC address is required"
      return 1
    fi
  else
    echo "📍 MAC Address: $MAC_ADDRESS"
  fi
  echo
  
  # Step 6: Save to JSON config file
  local datetime=$(date '+%Y-%m-%d %H:%M:%S')
  
  # Create new TV object and add to config
  local new_tv=$(jq -n \
    --arg ip "$TV_IP" \
    --arg name "$TV_NAME" \
    --arg mac "$MAC_ADDRESS" \
    --arg date "$datetime" \
    '{
      ip: $ip,
      name: $name,
      mac: $mac,
      date_added: $date,
      enabled_features: {
        waybar_volume_control: false,
        brightness_control: false
      }
    }')
  
  # Add to existing config
  jq --argjson new_tv "$new_tv" '.tvs += [$new_tv]' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"
  
  echo "✅ TV saved to configuration"
}

remove_tv() {
  local ip="$1"
  local config_file="$HOME/.config/lgtv/config.json"
  
  if [ -z "$ip" ]; then
    echo "❌ IP address required for TV removal"
    return 1
  fi
  
  if [ ! -f "$config_file" ]; then
    echo "❌ Config file not found"
    return 1
  fi
  
  # Get TV name for confirmation
  local tv_name=$(jq -r --arg ip "$ip" '.tvs[] | select(.ip == $ip) | .name' "$config_file")
  
  # Ask for confirmation
  echo "⚠️ You are about to remove TV: $tv_name ($ip)"
  if ! gum confirm "Are you sure you want to remove this TV?"; then
    echo "ℹ️ TV removal cancelled"
    return 0
  fi
  
  # Remove TV with matching IP from JSON config
  jq --arg ip "$ip" '.tvs |= map(select(.ip != $ip))' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"
  echo "✅ TV with IP $ip removed from configuration"
  
  return 0
}

tv_details() {
  local tv_name="$1"
  local tv_ip="$2"
  
  echo "📺 Selected TV: $tv_name"
  
  # Get TV details from JSON config file
  local config_file="$HOME/.config/lgtv/config.json"
  local mac_address=$(jq -r --arg ip "$tv_ip" '.tvs[] | select(.ip == $ip) | .mac' "$config_file")
  local date_added=$(jq -r --arg ip "$tv_ip" '.tvs[] | select(.ip == $ip) | .date_added' "$config_file")
  
  if [ -n "$mac_address" ] && [ "$mac_address" != "null" ]; then
    echo "📍 MAC Address: $mac_address"
  fi
  if [ -n "$date_added" ] && [ "$date_added" != "null" ]; then
    echo "📅 Date Added: $date_added"
  fi
  echo
  
  test_connection "$tv_ip"
  echo
  
  # Show TV options menu regardless of connection result
  TV_OPTIONS=(
    "Delete TV from config"
    "Start on boot"
    "Turn off on shutdown" 
    "Volume control"
    "Brightness control"
    "← Back"
  )
  TV_ACTION=$(gum choose --header "Select action for $tv_name:" "${TV_OPTIONS[@]}")
  
  case "$TV_ACTION" in
    "Delete TV from config")
      echo "🗑️ Deleting TV from config: $tv_name"
      remove_tv "$tv_ip"
      ;;
    "Start on boot")
      manage_boot_hook "$tv_ip" "$tv_name"
      ;;
    "Turn off on shutdown")
      manage_shutdown_hook "$tv_ip" "$tv_name"
      ;;
    "Volume control")
      manage_volume_control "$tv_ip" "$tv_name"
      ;;
    "Brightness control")
      manage_brightness_control "$tv_ip" "$tv_name"
      ;;
    "← Back")
      return 0
      ;;
  esac
}