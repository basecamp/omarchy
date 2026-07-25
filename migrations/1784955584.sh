echo "Track tmux output while its terminal is unfocused"

tmux_config="$HOME/.config/tmux/tmux.conf"

if [[ -f $tmux_config ]] && ! grep -q 'client-focus-out\[100\].*omarchy-tmux-alert track' "$tmux_config"; then
  sed -i \
    -e 's|^set-hook -g after-select-window .*|set-hook -g after-select-window '"'"'run-shell -b "omarchy-tmux-alert track #{window_id} #{window_activity}"'"'"'|' \
    -e 's|^set-hook -g client-session-changed .*|set-hook -g client-session-changed '"'"'run-shell -b "omarchy-tmux-alert track #{window_id} #{window_activity}"'"'"'|' \
    "$tmux_config"

  cat >>"$tmux_config" <<'EOF'
set-hook -g client-focus-out[100] 'run-shell -b "omarchy-tmux-alert track #{window_id} #{window_activity}"'
set-hook -g client-focus-in[100] 'run-shell -b "omarchy-tmux-alert track #{window_id} #{window_activity}"'
EOF

  omarchy-restart-tmux
fi
