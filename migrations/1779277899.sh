echo "Rename shell plugins"

config_files=(
  "$HOME/.config/hypr/bindings/utilities.lua"
  "$HOME/.config/hypr/bindings.lua"
  "$HOME/.config/hypr/apps/omarchy-shell.lua"
  "$HOME/.config/omarchy/omarchy-menu.jsonc"
  "$HOME/.config/omarchy/current/theme/shell.toml"
)

for config_file in "${config_files[@]}"; do
  if [[ -f $config_file ]]; then
    sed -i \
      -e 's/omarchy\.app-launcher/omarchy.launcher/g' \
      -e 's/omarchy\.battery-monitor/omarchy.battery/g' \
      -e 's/omarchy-app-launcher/omarchy-launcher/g' \
      -e 's/omarchy-battery-monitor/omarchy-battery/g' \
      -e 's/\[app-launcher\]/[launcher]/g' \
      -e 's/app-launcher\./launcher./g' \
      "$config_file"
  fi
done
