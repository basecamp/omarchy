#!/bin/bash
#
# Apply the HyprXero theme by copying configuration files.
# This script will back up any existing configs for the applications
# included in this theme before overwriting them.
#

# The directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
THEME_SOURCE_DIR="$SCRIPT_DIR/.config"
CONFIG_DEST_DIR="$HOME/.config"
BACKUP_PARENT_DIR="$HOME/config-backups-hyprxero-$(date +%Y%m%d-%H%M%S)"

echo "========================================"
echo " HyprXero Theme Application Script"
echo "========================================"
echo
echo "This script will overwrite existing configurations for:"
echo " - hypr"
echo " - kitty"
echo " - rofi"
echo " - waybar"
echo " - swaync"
echo " - wlogout"
echo
echo "Existing configurations will be backed up to:"
echo "$BACKUP_PARENT_DIR"
echo

read -p "Do you want to continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo
echo "--> Creating backup directory..."
mkdir -p "$BACKUP_PARENT_DIR"
if [ $? -ne 0 ]; then
    echo "Error: Could not create backup directory. Aborting."
    exit 1
fi

echo "--> Backing up and applying theme..."

# For each directory in our theme source, back it up if it exists, then copy it.
for dir in "$THEME_SOURCE_DIR"/*; do
    if [ -d "$dir" ]; then
        dir_name=$(basename "$dir")
        # Check if the destination directory exists
        if [ -d "$CONFIG_DEST_DIR/$dir_name" ]; then
            echo "    - Backing up existing '$dir_name' config..."
            mv "$CONFIG_DEST_DIR/$dir_name" "$BACKUP_PARENT_DIR/"
        fi
    fi
done

# Now, copy all the new theme files over
echo "    - Copying new theme files to $CONFIG_DEST_DIR..."
cp -r "$THEME_SOURCE_DIR"/* "$CONFIG_DEST_DIR/"

if [ $? -ne 0 ]; then
    echo "Error: Failed to copy theme files."
    echo "Your old configs (if any) are safe in $BACKUP_PARENT_DIR."
    exit 1
fi

echo
echo "========================================"
echo " Theme application complete!"
echo "========================================"
echo
echo "IMPORTANT:"
echo "This script does not install the necessary packages, fonts, or icons."
echo "You must install them manually for the theme to function correctly."
echo "Check the original HyprXero repository for a list of dependencies."
echo
