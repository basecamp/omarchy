# Copy over the keyboard layout that's been set in Arch during install to Hyprland
conf="/etc/vconsole.conf"
hyprconf="$HOME/.config/hypr/input.conf"

if grep -q '^KEYMAP=' "$conf"; then
  keymap=$(grep '^KEYMAP=' "$conf" | cut -d= -f2 | tr -d '"')

  layout=""
  variant=""

  case "$keymap" in
  de_CH*)
    layout="ch"
    variant="de"
    ;;
  fr_CH*)
    layout="ch"
    variant="fr"
    ;;
  *)
    layout="$keymap"
    ;;
  esac

  # Write to hypr config
  if [[ -n "$layout" ]]; then
    sed -i "/^[[:space:]]*kb_options *=/i\  kb_layout = $layout" "$hyprconf"
  fi
  if [[ -n "$variant" ]]; then
    sed -i "/^[[:space:]]*kb_options *=/i\  kb_variant = $variant" "$hyprconf"
  fi
fi
