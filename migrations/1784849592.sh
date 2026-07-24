echo "Add tmux hooks that surface waiting windows in the bar"

tmux_config="$HOME/.config/tmux/tmux.conf"

if [[ -f $tmux_config ]] && ! grep -q 'alert-bell' "$tmux_config"; then
  cat >>"$tmux_config" <<'EOF'

# Alerts
set-hook -g alert-bell 'run-shell -b "omarchy-shell -q omarchy.indicators refresh"'
set-hook -g alert-activity 'run-shell -b "omarchy-shell -q omarchy.indicators refresh"'
set-hook -g alert-silence 'run-shell -b "omarchy-shell -q omarchy.indicators refresh"'
set-hook -g after-select-window 'run-shell -b "omarchy-shell -q omarchy.indicators refresh"'
set-hook -g client-session-changed 'run-shell -b "omarchy-shell -q omarchy.indicators refresh"'
EOF

  omarchy-restart-tmux
fi
