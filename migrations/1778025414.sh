echo "Add two-column tdl option to tmux configuration"

TMUX_CONF=~/.config/tmux/tmux.conf

if [[ -f $TMUX_CONF ]]; then
  if ! grep -q "@omarchy-tdl-bottom-pane" "$TMUX_CONF"; then
    sed -i '/bind -n M-Down switch-client -n/a\
\
# on -> three panes; off -> two columns\
set -g @omarchy-tdl-bottom-pane on' "$TMUX_CONF"
    omarchy-restart-tmux
  fi
fi
