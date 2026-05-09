echo "Fix monitor scaling shortcut conflict on alternative keyboard layouts"

MONITOR_CONF="$HOME/.config/hypr/monitors.conf"
TILING_CONF="$HOME/.config/hypr/tiling-v2.conf"

# Update monitors.conf if it has the old code:61 bindings
if [[ -f $TILING_CONF ]]; then
  sed -i 's/SUPER, code:61, Cycle monitor scaling/SUPER, code:60, Cycle monitor scaling/' "$TILING_CONF"
  sed -i 's/SUPER ALT, code:61, Cycle monitor scaling backwards/SUPER ALT, code:60, Cycle monitor scaling backwards/' "$TILING_CONF"
fi
