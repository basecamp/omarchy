echo "Add Ctrl+n/Ctrl+p navigation keybinds to Walker"

CONFIG_FILE="$HOME/.config/walker/config.toml"

if [[ -f $CONFIG_FILE ]] &&
  grep -q '^quick_activate = \[\]' "$CONFIG_FILE" &&
  ! grep -qE '^next =' "$CONFIG_FILE" &&
  ! grep -qE '^previous =' "$CONFIG_FILE"; then
  sed -i '/^quick_activate = \[\]/a next = ["Down", "ctrl n"]     # move selection down (ctrl n like Vim/readline)\nprevious = ["Up", "ctrl p"]   # move selection up (ctrl p like Vim/readline)' "$CONFIG_FILE"
fi
