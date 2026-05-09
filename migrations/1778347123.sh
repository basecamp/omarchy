echo "Fix Waybar clock timezone by explicitly setting system timezone"

WAYBAR_CONF="$HOME/.config/waybar/config.jsonc"
if [[ -f $WAYBAR_CONF ]] && ! grep -q '"timezone"' "$WAYBAR_CONF"; then
  sed -i 's/"format": "{:L%A %H:%M}"/"format": "{:L%A %H:%M}",\n    "timezone": ""/' "$WAYBAR_CONF"
fi
