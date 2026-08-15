echo "Add a Tmux keybindings menu"

tmux_config="$HOME/.config/tmux/tmux.conf"

if [[ -f $tmux_config ]] && ! grep -q "omarchy-menu-tmux-keybindings" "$tmux_config"; then
  if ! grep -Eq '^[[:space:]]*bind(-key)?[[:space:]]+(\?|-T[[:space:]]+prefix[[:space:]]+\?)' "$tmux_config"; then
    if grep -q '^bind q source-file .*Configuration reloaded' "$tmux_config"; then
      sed -i '/^bind q source-file .*Configuration reloaded/a bind ? display-popup -E -w 80% -h 70% -T "Tmux keybindings" "omarchy-menu-tmux-keybindings --print | less -R"' "$tmux_config"
    else
      printf '\n# Keybinding help\nbind ? display-popup -E -w 80%% -h 70%% -T "Tmux keybindings" "omarchy-menu-tmux-keybindings --print | less -R"\n' >> "$tmux_config"
    fi

    omarchy-restart-tmux
  fi
fi
