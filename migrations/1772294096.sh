echo "Add Alt+Arrow keybindings for tmux window and session navigation"

TMUX_CONF=~/.config/tmux/tmux.conf

if [[ -f $TMUX_CONF ]]; then
  # Add M-Left/M-Right after M-9 if not present
  if ! grep -q "bind -n M-Left select-window" "$TMUX_CONF"; then
    sed -i '/bind -n M-9 select-window -t 9/a\
bind -n M-Left select-window -t -1\
bind -n M-Right select-window -t +1' "$TMUX_CONF"
  fi

  # Add M-Up/M-Down after "bind N switch-client -n" if not present
  if ! grep -q "bind -n M-Up switch-client" "$TMUX_CONF"; then
    sed -i '/^bind N switch-client -n$/a\
bind -n M-Up switch-client -p\
bind -n M-Down switch-client -n' "$TMUX_CONF"
  fi

  omarchy-restart-tmux
fi
