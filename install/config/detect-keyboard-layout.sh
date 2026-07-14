# Copy over the keyboard layout that's been set in Arch during install to Hyprland
conf="/etc/vconsole.conf"
hyprlua="$HOME/.config/hypr/input.lua"

if [[ -f $conf && -f $hyprlua ]]; then
  layout=$(grep '^XKBLAYOUT=' "$conf" | cut -d= -f2 | tr -d '"')
  variant=$(grep '^XKBVARIANT=' "$conf" | cut -d= -f2 | tr -d '"')

  # Layouts that can't type Latin characters get us first, so passwords and commands can always be typed
  if [[ $layout =~ ^(af|am|ara|bd|bg|by|et|ge|gr|il|in|iq|ir|kg|kh|kz|la|lk|mk|mm|mn|mv|np|rs|ru|sy|th|tj|ua)$ ]]; then
    layout="us,$layout"
    [[ -n $variant ]] && variant=",$variant"
  fi

  [[ -n $layout ]] && sed -i "/^[[:space:]]*kb_options *=/i\    kb_layout = \"$layout\"," "$hyprlua"
  [[ -n $variant ]] && sed -i "/^[[:space:]]*kb_options *=/i\    kb_variant = \"$variant\"," "$hyprlua"

  # Enable switching between layouts with Left Alt + Right Alt when there's more than one
  if [[ $layout == *,* ]]; then
    sed -i '/^[[:space:]]*kb_options/s/",[[:space:]]*--[[:space:]]*,grp:alts_toggle/,grp:alts_toggle",/' "$hyprlua"
  fi
fi
