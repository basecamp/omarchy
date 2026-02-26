# Configure ASUS ROG Aura key for media controls

if omarchy-hw-asus-rog; then
  echo "Configuring ASUS ROG keybindings"

  if ! grep -q "asus-rog.conf" ~/.config/hypr/hyprland.conf 2>/dev/null; then
    sed -i '/source = ~\/.local\/share\/omarchy\/default\/hypr\/bindings\/media.conf/a source = ~/.local/share/omarchy/default/hypr/bindings/asus-rog.conf' ~/.config/hypr/hyprland.conf
  fi
fi
