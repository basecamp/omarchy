echo "Add Alt+-/= keybindings for tmux pane resizing"

TMUX_CONF=~/.config/tmux/tmux.conf

if [[ -f $TMUX_CONF ]]; then
  # Add M--/M-=/M-_/M-+ after C-M-S-Right resize-pane if not present
  if ! grep -q "bind -n M-- resize-pane" "$TMUX_CONF"; then
    sed -i '/bind -n C-M-S-Right resize-pane -R 5/a\
\
bind -n M-- resize-pane -L 5\
bind -n M-= resize-pane -R 5\
bind -n M-_ resize-pane -U 5\
bind -n M-+ resize-pane -D 5' "$TMUX_CONF"
  fi

  omarchy-restart-tmux
fi
