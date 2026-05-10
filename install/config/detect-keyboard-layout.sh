# Copy over the keyboard layout that's been set in Arch during install to Hyprland
conf="/etc/vconsole.conf"
hyprlua="$HOME/.config/hypr/input.lua"

if [[ -f $conf && -f $hyprlua ]] && grep -q '^XKBLAYOUT=' "$conf"; then
  layout=$(grep '^XKBLAYOUT=' "$conf" | cut -d= -f2 | tr -d '"')
  sed -i "/^[[:space:]]*kb_options *=/i\    kb_layout = \"$layout\"," "$hyprlua"
fi

if [[ -f $conf && -f $hyprlua ]] && grep -q '^XKBVARIANT=' "$conf"; then
  variant=$(grep '^XKBVARIANT=' "$conf" | cut -d= -f2 | tr -d '"')
  sed -i "/^[[:space:]]*kb_options *=/i\    kb_variant = \"$variant\"," "$hyprlua"
fi
