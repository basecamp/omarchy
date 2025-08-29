#!/bin/bash

# Simple restore script for Omarchy configuration backup
# Usage: ./restore.sh [config_name]
# Example: ./restore.sh hypr (restores only hypr config)
# Example: ./restore.sh (interactive mode to choose what to restore)

BACKUP_DIR="$(dirname "$0")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

if [ "$1" ]; then
  # Restore specific config
  CONFIG_NAME="$1"
  BACKUP_PATH="$BACKUP_DIR/.config/$CONFIG_NAME"
  RESTORE_PATH="$HOME/.config/$CONFIG_NAME"

  if [ -e "$BACKUP_PATH" ]; then
    echo -e "${YELLOW}Restoring $CONFIG_NAME...${NC}"
    cp -r "$BACKUP_PATH" "$RESTORE_PATH"
    echo -e "${GREEN}Restored: ~/.config/$CONFIG_NAME${NC}"
  else
    echo -e "${RED}Backup not found for: $CONFIG_NAME${NC}"
    exit 1
  fi
else
  # Interactive mode
  echo "Available backups to restore:"
  find "$BACKUP_DIR/.config" -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | grep -v '^.config$' | sort
  echo ""
  echo "Usage: $0 <config_name>"
  echo "Example: $0 hypr"
fi
