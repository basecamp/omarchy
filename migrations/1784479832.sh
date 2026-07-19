echo "Enable Kitty cwd lookup through a remote control socket"

kitty_config="$HOME/.config/kitty/kitty.conf"
listen_on='listen_on unix:${XDG_RUNTIME_DIR}/omarchy-kitty-{kitty_pid}'

if [[ -f $kitty_config ]] && ! grep -qE '^[[:space:]]*listen_on[[:space:]]' "$kitty_config"; then
  printf '\n# Allow cwd lookup from global keybindings\n%s\n' "$listen_on" >>"$kitty_config"
fi
