echo "Make shift+insert paste from clipboard"
sed -i '/keybind = f11=toggle_fullscreen/a keybind = shift+insert=paste_from_clipboard' ~/.config/ghostty/config
sed -i 's/{ key = "F11", action = "ToggleFullscreen" }/{ key = "F11", action = "ToggleFullscreen" },\n{ key = "Insert", mods = "Shift", action = "Paste" }/' ~/.config/alacritty/alacritty.toml
