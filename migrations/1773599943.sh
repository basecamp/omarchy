echo "Add COPY mode indicator to tmux status bar"

if [[ -f ~/.config/tmux/tmux.conf ]]; then
  if ! grep -q "pane_in_mode" ~/.config/tmux/tmux.conf; then
    sed -i 's/#{?client_prefix/#{?pane_in_mode,COPY ,}#{?client_prefix/' ~/.config/tmux/tmux.conf
    omarchy-restart-tmux
  fi
fi
