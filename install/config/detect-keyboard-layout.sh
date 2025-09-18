# Copy over the keyboard layout that's been set in Arch during install to Hyprland
conf="/etc/vconsole.conf"
hyprconf="$HOME/.config/hypr/input.conf"

# Extract layout and variant if they exist
layout=""
variant=""

if grep -q '^XKBLAYOUT=' "$conf"; then
  layout=$(grep '^XKBLAYOUT=' "$conf" | cut -d= -f2 | tr -d '"')
fi

if grep -q '^XKBVARIANT=' "$conf"; then
  variant=$(grep '^XKBVARIANT=' "$conf" | cut -d= -f2 | tr -d '"')
fi

# Combine layout and variant in the format Hyprland expects
if [ -n "$layout" ]; then
  if [ -n "$variant" ]; then
    # Hyprland expects format like "de(mac)" for layouts with variants
    kb_layout="${layout}(${variant})"
  else
    kb_layout="$layout"
  fi

  # Insert the kb_layout line before kb_options
  sed -i "/^[[:space:]]*kb_options *=/i\  kb_layout = $kb_layout" "$hyprconf"
fi