echo "Add Alt+Enter and Alt+Shift+Enter split keybindings to tmux"

tmux_config="$HOME/.config/tmux/tmux.conf"

if [[ -f $tmux_config ]]; then
  changed=0

  if ! grep -qxF 'bind -n M-Enter split-window -v -c "#{pane_current_path}"' "$tmux_config"; then
    printf '\nbind -n M-Enter split-window -v -c "#{pane_current_path}"\n' >>"$tmux_config"
    changed=1
  fi

  if ! grep -qxF 'bind -n M-S-Enter split-window -h -c "#{pane_current_path}"' "$tmux_config"; then
    printf 'bind -n M-S-Enter split-window -h -c "#{pane_current_path}"\n' >>"$tmux_config"
    changed=1
  fi

  if (( changed )); then
    omarchy-restart-tmux
  fi
fi
