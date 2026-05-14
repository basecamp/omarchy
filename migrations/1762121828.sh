echo "Setting up xdg-terminal-exec for gtk-launch terminal support"
# Solve for hardcoded glib terminals
# https://github.com/basecamp/omarchy/issues/1852

# Remove old symlink if it exists -- if someone ran the previous migration early
if [[ -L /usr/local/bin/xdg-terminal-exec ]]; then
  sudo rm /usr/local/bin/xdg-terminal-exec
fi

omarchy-pkg-add xdg-terminal-exec

# Set up xdg-terminals.list based on current $TERMINAL
if [[ -n $TERMINAL ]]; then
  case "$TERMINAL" in
  alacritty) desktop_id="Alacritty.desktop" ;;
  ghostty) desktop_id="com.mitchellh.ghostty.desktop" ;;
  kitty) desktop_id="kitty.desktop" ;;
  esac

  if [[ -n $desktop_id ]]; then
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

# Update TERMINAL variable in uwsm config
sed -i 's/export TERMINAL=.*/export TERMINAL=xdg-terminal-exec/' ~/.config/uwsm/default
