echo "Add extended-keys to tmux configuration"

if [[ -f ~/.config/tmux/tmux.conf ]]; then
  if ! grep -q "set -g extended-keys on" ~/.config/tmux/tmux.conf; then
    sed -i '/^# Prefix$/i\
# Extended keys for complex bindings (Ctrl+Shift+*, etc)\
set -g extended-keys on\
' ~/.config/tmux/tmux.conf
    omarchy-restart-tmux
  fi
fi