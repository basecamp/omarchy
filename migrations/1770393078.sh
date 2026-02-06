echo "Add async-backend = epoll to ghostty config to fix high IO pressure"

if [[ -f ~/.config/ghostty/config ]] && ! grep -q "^async-backend" ~/.config/ghostty/config; then
  echo "" >> ~/.config/ghostty/config
  echo "# Fix general slowness on hyprland (https://github.com/ghostty-org/ghostty/discussions/3224)" >> ~/.config/ghostty/config
  echo "async-backend = epoll" >> ~/.config/ghostty/config
fi
