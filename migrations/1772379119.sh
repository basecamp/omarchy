echo "Add Alt+Shift+Arrow keybindings for swapping tmux windows"

TMUX_CONF=~/.config/tmux/tmux.conf

if [[ -f $TMUX_CONF ]]; then
  if ! grep -q "bind -n M-S-Left swap-window" "$TMUX_CONF"; then
    sed -i '/bind -n M-Right select-window -t +1/a\
bind -n M-S-Left swap-window -t -1 \\; select-window -t -1\
bind -n M-S-Right swap-window -t +1 \\; select-window -t +1' "$TMUX_CONF"
  fi

  omarchy-restart-tmux
fi
