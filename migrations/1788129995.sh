echo "Enable workspace assignments from nwg-displays"

hyprland_config="$HOME/.config/hypr/hyprland.lua"

if [[ -f $hyprland_config ]] &&
  grep -Fq 'require("hypr.monitors")' "$hyprland_config" &&
  ! grep -Fq 'hypr.workspaces' "$hyprland_config"; then
  tmp=$(mktemp)

  awk '
    { print }

    !inserted && $0 == "require(\"hypr.monitors\")" {
      print "local require_optional = require(\"default.hypr.require_optional\")"
      print "require_optional.module(\"hypr.workspaces\")"
      inserted = 1
    }
  ' "$hyprland_config" >"$tmp"

  cat "$tmp" >"$hyprland_config"
  rm -f "$tmp"
fi
