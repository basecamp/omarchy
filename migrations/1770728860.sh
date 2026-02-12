echo "Unbind ctrl+shift+left/right in Ghostty so it doesn't interfere with tmux keybindings"

if ! grep -q "keybind = ctrl+shift+left=" ~/.config/ghostty/config; then
  sed -i '/# Keyboard bindings/a\keybind = ctrl+shift+left=unbind\nkeybind = ctrl+shift+right=unbind' ~/.config/ghostty/config
fi
