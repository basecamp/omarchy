echo "Remove standalone night light, brightness, power profile, and power menu bar widgets (moved into quick settings or removed)"

config="$HOME/.config/omarchy/shell.json"
[[ -f $config ]] || return 0

if ! grep -Eq '"id": *"(nightLight|brightness|powerProfile|powerMenu)"' "$config"; then
  return 0
fi

if omarchy-cmd-missing jq; then
  return 0
fi

tmp=$(mktemp)
if jq '
  def keep_widget: select(.id != "nightLight" and .id != "brightness" and .id != "powerProfile" and .id != "powerMenu");
  .bar.layout.left   |= map(keep_widget) |
  .bar.layout.center |= map(keep_widget) |
  .bar.layout.right  |= map(keep_widget)
' "$config" > "$tmp" 2>/dev/null && [[ -s $tmp ]]; then
  mv "$tmp" "$config"
else
  rm -f "$tmp"
fi
