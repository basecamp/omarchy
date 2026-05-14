echo "Add Alt+Enter smart split keybinding to tmux"

tmux_config="$HOME/.config/tmux/tmux.conf"

if [[ -f $tmux_config ]] && ! grep -q "bind -n M-Enter run-shell" "$tmux_config"; then
  if grep -q '^bind ? display-popup .*omarchy-menu-tmux-keybindings' "$tmux_config"; then
    sed -i '/^bind ? display-popup .*omarchy-menu-tmux-keybindings/a bind -n M-Enter run-shell \\
"[[ $(tmux list-panes | wc -l) -eq 1 ]] \&\& \\
tmux splitw -h -c '\''#{pane_current_path}'\'' || \\
tmux splitw -v -c '\''#{pane_current_path}'\''"' "$tmux_config"
  elif grep -q '^bind q source-file .*Configuration reloaded' "$tmux_config"; then
    sed -i '/^bind q source-file .*Configuration reloaded/a bind -n M-Enter run-shell \\
"[[ $(tmux list-panes | wc -l) -eq 1 ]] \&\& \\
tmux splitw -h -c '\''#{pane_current_path}'\'' || \\
tmux splitw -v -c '\''#{pane_current_path}'\''"' "$tmux_config"
  else
    cat >>"$tmux_config" <<'EOF'

# Smart split: horizontal from one pane, vertical otherwise
bind -n M-Enter run-shell \
"[[ $(tmux list-panes | wc -l) -eq 1 ]] && \
tmux splitw -h -c '#{pane_current_path}' || \
tmux splitw -v -c '#{pane_current_path}'"
EOF
  fi

  omarchy-restart-tmux
fi
