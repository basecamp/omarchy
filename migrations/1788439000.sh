echo "Load personal hypr.envs from the Hyprland entrypoint"

# 4.x dropped the personal envs require that 3.x had via envs.conf. The updater
# still patches ~/.config/hypr/envs.lua, but nothing loaded it (#9902).

hyprland_config="$HOME/.config/hypr/hyprland.lua"
[[ -f $hyprland_config ]] || exit 0

if grep -Eq 'require(_optional\.module)?\(["'\'']hypr\.envs["'\'']\)|require_optional\.module\(["'\'']hypr\.envs["'\'']\)' "$hyprland_config"; then
  exit 0
fi

tmp=$(mktemp)
awk '
  BEGIN { inserted = 0 }
  {
    print
    if (!inserted && $0 ~ /^require\("hypr\.autostart"\)/) {
      print "-- Personal env overrides (after package defaults so user hl.env wins)."
      print "local require_optional = require(\"default.hypr.require_optional\")"
      print "require_optional.module(\"hypr.envs\")"
      inserted = 1
    }
  }
  END {
    if (!inserted) {
      print "-- Personal env overrides (after package defaults so user hl.env wins)."
      print "local require_optional = require(\"default.hypr.require_optional\")"
      print "require_optional.module(\"hypr.envs\")"
    }
  }
' "$hyprland_config" >"$tmp"
cat "$tmp" >"$hyprland_config"
rm -f "$tmp"
