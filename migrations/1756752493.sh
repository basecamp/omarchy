#!/bin/bash

echo "Add Separate profile support for Omarchy web applications"

sed -i 's/\[ "\$#" -ne 3 \]/[ "\$#" -ne 4 ]/' "$HOME/.local/share/omarchy/bin/omarchy-webapp-install"
sed -i '/ICON_URL=$(gum input/ a\  PROFILE=$(gum input --prompt "Separate Profile?> " --placeholder "Leave it blank for a shared profile, or type "YES" for a separate profile (multiple instances)")' "$HOME/.local/share/omarchy/bin/omarchy-webapp-install"

sed -i '/ICON_URL="\$3"/ a\  PROFILE="$4"' "$HOME/.local/share/omarchy/bin/omarchy-webapp-install"

sed -i '/^ICON_DIR=/ i \
if [ "$PROFILE" != "" ]; then \
  USER_DATA_DIR="$HOME/.cache/ChromiumInstances/$APP_NAME" \
  mkdir -p "$USER_DATA_DIR" \
  USER_DATA_DIR="--user-data-dir=${USER_DATA_DIR}" \
else \
  USER_DATA_DIR="" \
fi \
' "$HOME/.local/share/omarchy/bin/omarchy-webapp-install"

sed -i 's|^Exec=omarchy-launch-webapp \$APP_URL$|Exec=omarchy-launch-webapp $APP_URL $USER_DATA_DIR|' "$HOME/.local/share/omarchy/bin/omarchy-webapp-install"