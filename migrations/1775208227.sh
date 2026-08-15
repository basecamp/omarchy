echo "Remove misleading waybar network transfer speeds"

if grep -q "bandwidthDownBytes" ~/.config/waybar/config.jsonc; then
  sed -i 's/"tooltip-format-wifi": "{essid} ({frequency} GHz)\\n⇣{bandwidthDownBytes}  ⇡{bandwidthUpBytes}"/"tooltip-format-wifi": "{essid} ({frequency} GHz)"/' ~/.config/waybar/config.jsonc
  sed -i 's/"tooltip-format-ethernet": "⇣{bandwidthDownBytes}  ⇡{bandwidthUpBytes}"/"tooltip-format-ethernet": "Connected"/' ~/.config/waybar/config.jsonc
  omarchy-restart-waybar
fi
