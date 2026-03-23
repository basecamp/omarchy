echo "Add ASUS keyboard support for makima key remapping (ROG devices only)"

if [[ -f "$HOME/.config/makima/AT Translated Set 2 keyboard.toml" ]] && omarchy-hw-asus-rog && [[ ! -e "$HOME/.config/makima/Asus Keyboard.toml" ]]; then
  ln -sf "AT Translated Set 2 keyboard.toml" "$HOME/.config/makima/Asus Keyboard.toml"
fi
