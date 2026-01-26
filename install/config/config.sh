# Copy over Omarchy configs
mkdir -p ~/.config
cp -R ~/.local/share/omarchy/config/* ~/.config/

# For lite edition, use kitty as default terminal instead of ghostty
if [[ "${OMARCHY_EDITION:-full}" == "lite" ]]; then
  cat > ~/.config/xdg-terminals.list << EOF
# Terminal emulator preference order for xdg-terminal-exec
# The first found and valid terminal will be used
kitty.desktop
EOF

  # Add lite-specific keybindings (Ctrl+Shift+Esc for task manager, etc.)
  if ! grep -q "bindings-lite.conf" ~/.config/hypr/hyprland.conf; then
    echo "" >> ~/.config/hypr/hyprland.conf
    echo "# Lite edition keybindings" >> ~/.config/hypr/hyprland.conf
    echo "source = ~/.config/hypr/bindings-lite.conf" >> ~/.config/hypr/hyprland.conf
  fi

  # Use lite hypridle config (no screensaver, just turn off display to save energy)
  cp ~/.local/share/omarchy/config/hypr/hypridle-lite.conf ~/.config/hypr/hypridle.conf
fi

# Use default bashrc from Omarchy
cp ~/.local/share/omarchy/default/bashrc ~/.bashrc
