echo "Setting up xdg-terminal-exec for gtk-launch terminal support"
# Solve for hardcoded glib terminals
# https://github.com/basecamp/omarchy/issues/1852

# Remove old symlink if it exists -- if someone ran the previous migration early
if [ -L /usr/local/bin/xdg-terminal-exec ]; then
  sudo rm /usr/local/bin/xdg-terminal-exec
fi

omarchy-pkg-add xdg-terminal-exec

# Set up xdg-terminals.list based on current $TERMINAL
if [ -n "$TERMINAL" ]; then
  case "$TERMINAL" in
  alacritty) desktop_id="Alacritty.desktop" ;;
  ghostty) desktop_id="com.mitchellh.ghostty.desktop" ;;
  kitty) desktop_id="kitty.desktop" ;;
  esac

  if [ -n "$desktop_id" ]; then
    mkdir -p ~/.config
    cat > ~/.config/xdg-terminals.list << EOF
# Terminal emulator preference order for xdg-terminal-exec
# The first found and valid terminal will be used
$desktop_id
EOF
  fi
fi

# Copy custom desktop entries with proper X-TerminalArg* keys
if command -v alacritty > /dev/null 2>&1; then
  cp "$OMARCHY_PATH/applications/Alacritty.desktop" ~/.local/share/applications/
fi

# Update hyprland bindings to use xdg-terminal-exec
sed -i 's/\$terminal = uwsm-app -- \$TERMINAL/$terminal = uwsm-app -- xdg-terminal-exec/' ~/.config/hypr/bindings.conf
# Update --working-directory to --dir for xdg-terminal-exec
sed -i 's/--working-directory=/--dir=/g' ~/.config/hypr/bindings.conf

# Update TERMINAL variable in uwsm config
sed -i 's/export TERMINAL=.*/export TERMINAL=xdg-terminal-exec/' ~/.config/uwsm/default

# Update waybar config to use xdg-terminal-exec
waybar_config=~/.config/waybar/config.jsonc
if [ -f "$waybar_config" ]; then
  sed -i 's|"on-click-right": "omarchy-launch-terminal"|"on-click-right": "xdg-terminal-exec"|' "$waybar_config"
  sed -i 's|"on-click": "\$TERMINAL -e btop"|"on-click": "xdg-terminal-exec btop"|' "$waybar_config"
  sed -i 's|"on-click": "\$TERMINAL --class=Wiremix -e wiremix"|"on-click": "xdg-terminal-exec --app-id=com.omarchy.Wiremix -e wiremix"|' "$waybar_config"
  omarchy-state set restart-waybar-required
fi

# Update hyprland window rules to use DNS-format class names
system_conf=~/.config/hypr/apps/system.conf
if [ -f "$system_conf" ]; then
  if grep -q 'class:(.*|Impala|' "$system_conf" || grep -q 'class:(.*|Wiremix|' "$system_conf" || grep -q '|Omarchy|' "$system_conf"; then
    sed -i 's/\bImpala\b/com.omarchy.Impala/g; s/\bWiremix\b/com.omarchy.Wiremix/g; s/|Omarchy|/|com.omarchy.Omarchy|/g' "$system_conf"
  fi
fi
