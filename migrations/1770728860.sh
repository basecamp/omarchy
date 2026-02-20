echo "Unbind ctrl+shift+page_up/page_down in Ghostty so it doesn't interfere with tmux keybindings"

if [[ -f ~/.config/ghostty/config ]] && ! grep -q "keybind = ctrl+shift+page_up=" ~/.config/ghostty/config; then
  sed -i '/# Keyboard bindings/a\keybind = ctrl+shift+page_up=unbind\nkeybind = ctrl+shift+page_down=unbind' ~/.config/ghostty/config
fi
