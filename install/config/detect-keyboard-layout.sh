# Copy over the keyboard layout that's been set in Arch during install to Hyprland
conf="/etc/vconsole.conf"
hyprconf="$HOME/.config/hypr/input.conf"

default="us"
# Extract the primary keyboard layout (XKBLAYOUT) from vconsole.conf.
# We use grep to find the line, cut to get the value after '=', and tr to remove quotes.
layout=$(grep '^XKBLAYOUT=' "$conf" | cut -d= -f2 | tr -d '"')

# Extract the keyboard variant (XKBVARIANT) from vconsole.conf.
# This might be empty if no specific variant is used for the chosen layout.
variant=$(grep '^XKBVARIANT=' "$conf" | cut -d= -f2 | tr -d '"')

if [ "$layout" != "$default" ]; then
    kb_layout="$default,$layout"
    kb_variant=",$variant"
    kb_options="grp:alt_shift_toggle"
else
    kb_layout="$layout"
    kb_variant="$variant"
    kb_options=""
fi
sed -i "/^[[:space:]]*kb_layout *=/d" "$hyprconf"
sed -i "/^[[:space:]]*kb_variant *=/d" "$hyprconf"
sed -i "/^[[:space:]]*kb_options *=/d" "$hyprconf"

echo "kb_layout = $kb_layout" >> "$hyprconf"

[ -n "$kb_variant" ] && echo "kb_variant = $kb_variant" >> "$hyprconf"
[ -n "$kb_options" ] && echo "kb_options = $kb_options" >> "$hyprconf"