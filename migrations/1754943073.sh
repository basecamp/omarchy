#!/bin/bash

# Create new bin scripts
cat > "$HOME/.local/share/omarchy/bin/omarchy-toggle-screensaver" << 'EOF'
#!/bin/bash

STATE_FILE="$HOME/.local/state/omarchy/toggles/screensaver-off"

if [[ -f "$STATE_FILE" ]]; then
  rm -f "$STATE_FILE"
  notify-send "Screensaver enabled"
else
  mkdir -p "$(dirname "$STATE_FILE")"
  touch "$STATE_FILE"
  notify-send "Screensaver disabled"
fi
EOF

cat > "$HOME/.local/share/omarchy/bin/omarchy-launch-screensaver-if-enabled" << 'EOF'
#!/bin/bash

STATE_FILE="$HOME/.local/state/omarchy/toggles/screensaver-off"

if [[ ! -f "$STATE_FILE" ]]; then
  omarchy-launch-screensaver
fi
EOF

chmod +x "$HOME/.local/share/omarchy/bin/omarchy-toggle-screensaver"
chmod +x "$HOME/.local/share/omarchy/bin/omarchy-launch-screensaver-if-enabled"


# Backup files
backup_timestamp=$(date +"%Y%m%d%H%M%S")
cp "$HOME/.config/hypr/hypridle.conf" "$HOME/.config/hypr/hypridle.conf.bak.${backup_timestamp}"
cp "$HOME/.local/share/omarchy/bin/omarchy-menu" "$HOME/.local/share/omarchy/bin/omarchy-menu.bak.${backup_timestamp}"
echo "Backed up hypridle.conf and omarchy-menu to hypridle.conf.bak.${backup_timestamp} and omarchy-menu.bak.${backup_timestamp}"

# Update hypridle config and menu
sed -i 's/omarchy-launch-screensaver/omarchy-launch-screensaver-if-enabled/' "$HOME/.config/hypr/hypridle.conf"
sed -i 's/omarchy-launch-screensaver/omarchy-toggle-screensaver/' "$HOME/.local/share/omarchy/bin/omarchy-menu"