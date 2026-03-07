echo "Add automatic-rename settings to tmux configuration"

if [[ -f ~/.config/tmux/tmux.conf ]]; then
  if ! grep -q "set -gw automatic-rename on" ~/.config/tmux/tmux.conf; then
    sed -i '/set -g window-status-separator ""/a\
set -gw automatic-rename on\
set -gw automatic-rename-format '\''#{b:pane_current_path}'\'' \
' ~/.config/tmux/tmux.conf
    omarchy-restart-tmux
  fi
fi
