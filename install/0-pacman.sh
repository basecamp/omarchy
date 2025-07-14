#!/bin/bash

CONFIG_FILE="/etc/pacman.conf"

# Function to check if a key exists (uncommented) in the config
key_exists() {
  local key="$1"
  grep -q "^${key}$" "$CONFIG_FILE"
}

# Function to add a key to the [options] section
add_key() {
  local key="$1"

  if key_exists "$key"; then
    return 0
  fi

  # Add the key after the [options] line
  sudo sed -i "/^\[options\]/a $key" "$CONFIG_FILE"
}

# Add the keys
echo "Configuring pacman..."
add_key "Color"
add_key "ILoveCandy"
