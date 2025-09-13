#!/bin/bash

# Omarchy Configuration Backup Utility
# This script backs up existing configurations before Omarchy overwrites them

BACKUP_DIR="$HOME/.config/omarchy-backups"
BACKUP_TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_SESSION_DIR="$BACKUP_DIR/$BACKUP_TIMESTAMP"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# List of configuration directories/files that Omarchy will overwrite
CONFIG_ITEMS=(
  "hypr"
  "waybar" 
  "btop"
  "alacritty"
  "nvim"
  "fastfetch"
  "swayosd"
  "walker"
  "lazygit"
  "fontconfig"
  "fcitx5"
  "Typora"
  "chromium"
  "xournalpp"
  "systemd/user"
  "environment.d"
  "uwsm"
)

# Additional files that might be overwritten
CONFIG_FILES=(
  ".bashrc"
  ".config/starship.toml"
  ".config/brave-flags.conf"
  ".config/chromium-flags.conf"
)

echo "Omarchy Configuration Backup"
echo "============================"
echo ""

# Create backup directory structure
mkdir -p "$BACKUP_SESSION_DIR"
echo -e "${GREEN}Created backup directory: $BACKUP_SESSION_DIR${NC}"

# Function to backup a config directory or file
backup_config_item() {
  local item="$1"
  local source_path="$HOME/.config/$item"
  local backup_path="$BACKUP_SESSION_DIR/.config/$item"

  if [ -e "$source_path" ]; then
    echo -e "${YELLOW}Backing up: ~/.config/$item${NC}"
    mkdir -p "$(dirname "$backup_path")"
    cp -r "$source_path" "$backup_path"
    return 0
  else
    echo "No existing config found for: ~/.config/$item"
    return 1
  fi
}

# Function to backup a file
backup_file() {
  local file="$1"
  local source_path="$HOME/$file"
  local backup_path="$BACKUP_SESSION_DIR/$file"

  if [ -e "$source_path" ]; then
    echo -e "${YELLOW}Backing up: ~/$file${NC}"
    mkdir -p "$(dirname "$backup_path")"
    cp "$source_path" "$backup_path"
    return 0
  else
    echo "No existing file found: ~/$file"
    return 1
  fi
}

# Backup configuration directories
BACKED_UP_COUNT=0
echo "Backing up configuration directories..."
for config_item in "${CONFIG_ITEMS[@]}"; do
  if backup_config_item "$config_item"; then
    ((BACKED_UP_COUNT++))
  fi
done

# Backup individual files
echo ""
echo "Backing up configuration files..."
for config_file in "${CONFIG_FILES[@]}"; do
  if backup_file "$config_file"; then
    ((BACKED_UP_COUNT++))
  fi
done

echo ""

if [ $BACKED_UP_COUNT -gt 0 ]; then
  # Create a backup manifest
  echo "# Omarchy Configuration Backup Manifest" > "$BACKUP_SESSION_DIR/backup_manifest.txt"
  echo "# Created on: $(date)" >> "$BACKUP_SESSION_DIR/backup_manifest.txt"
  echo "# Backup location: $BACKUP_SESSION_DIR" >> "$BACKUP_SESSION_DIR/backup_manifest.txt"
  echo "# Items backed up: $BACKED_UP_COUNT" >> "$BACKUP_SESSION_DIR/backup_manifest.txt"
  echo "" >> "$BACKUP_SESSION_DIR/backup_manifest.txt"
  echo "This backup contains your original configurations before Omarchy installation." >> "$BACKUP_SESSION_DIR/backup_manifest.txt"
  echo "You can restore any of these configurations by copying them back to your ~/.config/ directory." >> "$BACKUP_SESSION_DIR/backup_manifest.txt"

  # Create a simple restore script
  cp ~/.local/share/omarchy/install/config/restore.sh "$BACKUP_SESSION_DIR/restore.sh"
  chmod +x "$BACKUP_SESSION_DIR/restore.sh"
  
  echo -e "${GREEN}Backup completed successfully!${NC}"
  echo "Backed up $BACKED_UP_COUNT configuration items"
  echo "Backup location: $BACKUP_SESSION_DIR"
  echo ""
  echo "To restore any configuration later:"
  echo "   cd $BACKUP_SESSION_DIR && ./restore.sh <config_name>"
  echo "   Example: cd $BACKUP_SESSION_DIR && ./restore.sh hypr"
  echo ""
else
  echo "No existing configurations found to backup."
  echo "This appears to be a fresh installation."
  # Remove empty backup directory
  rmdir "$BACKUP_SESSION_DIR" 2>/dev/null || true
  rmdir "$BACKUP_DIR" 2>/dev/null || true
fi

# Create or update the latest backup symlink for convenience
if [ $BACKED_UP_COUNT -gt 0 ]; then
  ln -sfn "$BACKUP_SESSION_DIR" "$BACKUP_DIR/latest"
  echo "Latest backup symlink: $BACKUP_DIR/latest"
fi
