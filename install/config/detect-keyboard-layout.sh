OMARCHY_DESCRIPTION="Keyboard Layout Config"

omarchy_install() {
  # Copy over the keyboard layout that's been set in Arch during install to Hyprland
  conf="/etc/vconsole.conf"
  hyprconf="$HOME/.config/hypr/input.conf"

  if grep -q '^XKBLAYOUT=' "$conf"; then
    layout=$(grep '^XKBLAYOUT=' "$conf" | cut -d= -f2 | tr -d '"')
    sed -i "/^[[:space:]]*kb_options *=/i\  kb_layout = $layout" "$hyprconf"
  fi

  if grep -q '^XKBVARIANT=' "$conf"; then
    variant=$(grep '^XKBVARIANT=' "$conf" | cut -d= -f2 | tr -d '"')
    sed -i "/^[[:space:]]*kb_options *=/i\  kb_variant = $variant" "$hyprconf"
  fi
}

omarchy_verify() {
  [[ -f "$HOME/.config/hypr/input.conf" ]] || add_error "Hyprland input config missing"

  # If vconsole.conf has keyboard layout, check if it's in hypr config
  if [[ -f "/etc/vconsole.conf" ]] && grep -q '^XKBLAYOUT=' "/etc/vconsole.conf"; then
    layout=$(grep '^XKBLAYOUT=' "/etc/vconsole.conf" | cut -d= -f2 | tr -d '"')
    if [[ -f "$HOME/.config/hypr/input.conf" ]]; then
      grep -q "kb_layout = $layout" "$HOME/.config/hypr/input.conf" || add_error "Keyboard layout not configured in Hyprland"
    fi
  fi
}
