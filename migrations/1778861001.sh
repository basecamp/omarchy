echo "Convert rounded-corners Hyprland toggle from conf to Lua"

toggle_state_dir="$HOME/.local/state/omarchy/toggles/hypr"
toggle_defaults_dir="$OMARCHY_PATH/default/hypr/toggles"
timestamp=$(date +%s)

conf_toggle="$toggle_state_dir/rounded-corners.conf"
lua_toggle="$toggle_state_dir/rounded-corners.lua"

mkdir -p "$toggle_state_dir"

if [[ -f $conf_toggle ]]; then
  if [[ ! -f $lua_toggle ]] && [[ -f $toggle_defaults_dir/rounded-corners.lua ]]; then
    cp -f "$toggle_defaults_dir/rounded-corners.lua" "$lua_toggle"
    echo "Converted rounded-corners toggle to Lua"
  fi

  mv "$conf_toggle" "$conf_toggle.bak.$timestamp"
fi
