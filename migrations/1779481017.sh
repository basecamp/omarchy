echo "Namespace Omarchy built-in bar widget ids in shell.json"

config_file="$HOME/.config/omarchy/shell.json"

if [[ -s $config_file ]] && jq -e 'type == "object" and .version == 1' "$config_file" >/dev/null 2>&1; then
  tmp=$(mktemp)
  jq '
    def canonical_widget_id:
      if . == "Omarchy" then "omarchy.menu"
      elif . == "Workspaces" then "omarchy.workspaces"
      elif . == "Media" then "omarchy.media"
      elif . == "AudioPanel" then "omarchy.audio"
      elif . == "MonitorPanel" then "omarchy.monitor"
      elif . == "NetworkPanel" then "omarchy.network"
      elif . == "PowerPanel" then "omarchy.power"
      elif . == "BluetoothPanel" then "omarchy.bluetooth"
      elif . == "Clock" then "omarchy.clock"
      elif . == "Indicators" then "omarchy.indicators"
      elif . == "NotificationCenter" then "omarchy.notifications"
      elif . == "SystemUpdate" then "omarchy.system-update"
      elif . == "SystemStats" then "omarchy.system-stats"
      elif . == "Tray" then "omarchy.tray"
      elif . == "Weather" then "omarchy.weather"
      elif . == "Microphone" then "omarchy.microphone"
      elif . == "ActiveWindow" then "omarchy.active-window"
      elif . == "KeyboardLayout" then "omarchy.keyboard-layout"
      elif . == "LockKeys" then "omarchy.lock-keys"
      elif . == "Spacer" then "omarchy.spacer"
      else . end;

    def canonical_entry:
      if type == "string" then canonical_widget_id
      elif type == "object" and has("id") then .id = (.id | canonical_widget_id)
      else . end;

    .bar.centerAnchor = ((.bar.centerAnchor // "") | canonical_widget_id) |
    .bar.layout.left = ((.bar.layout.left // []) | map(canonical_entry)) |
    .bar.layout.center = ((.bar.layout.center // []) | map(canonical_entry)) |
    .bar.layout.right = ((.bar.layout.right // []) | map(canonical_entry))
  ' "$config_file" >"$tmp" && mv "$tmp" "$config_file"
fi
