echo "Stop forcing Ghostty's epoll backend"

ghostty_config="$HOME/.config/ghostty/config"

[[ -f $ghostty_config ]] || exit 0

sed -i --follow-symlinks '\|^# Fix general slowness on hyprland (https://github\.com/ghostty-org/ghostty/discussions/3224)$| {
  $!N
  \|^# Fix general slowness on hyprland (https://github\.com/ghostty-org/ghostty/discussions/3224)\nasync-backend = epoll$|d
}' "$ghostty_config"
