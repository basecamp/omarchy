echo "Migrate Hyprland user config from Omarchy hyprlang files to Lua files"

hypr_config_dir="$HOME/.config/hypr"
omarchy_hypr_config_dir="$OMARCHY_PATH/config/hypr"
toggle_state_dir="$HOME/.local/state/omarchy/toggles/hypr"
toggle_defaults_dir="$OMARCHY_PATH/default/hypr/toggles"
timestamp=$(date +%s)

lua_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

mkdir -p "$hypr_config_dir" "$toggle_state_dir"

for lua_config in "$omarchy_hypr_config_dir"/*.lua "$omarchy_hypr_config_dir"/.luarc.json; do
  if [[ -f $lua_config ]]; then
    cp -f "$lua_config" "$hypr_config_dir/"
  fi
done

for config_name in autostart bindings hyprland input looknfeel monitors; do
  conf_file="$hypr_config_dir/$config_name.conf"

  if [[ -f $conf_file ]]; then
    mv "$conf_file" "$conf_file.bak.$timestamp"
  fi
done

for conf_toggle in "$toggle_state_dir"/*.conf; do
  [[ -f $conf_toggle ]] || continue

  toggle_name=$(basename "$conf_toggle" .conf)
  lua_toggle="$toggle_state_dir/$toggle_name.lua"

  if [[ ! -f $lua_toggle ]]; then
    case "$toggle_name" in
      flags | single-window-aspect-ratio | window-no-gaps)
        if [[ -f $toggle_defaults_dir/$toggle_name.lua ]]; then
          cp -f "$toggle_defaults_dir/$toggle_name.lua" "$lua_toggle"
        fi
        ;;
      internal-monitor-disable)
        monitor=$(sed -nE 's/^monitor=([^,]+),disable.*$/\1/p' "$conf_toggle" | head -n 1)
        if [[ -n $monitor ]]; then
          printf 'hl.monitor({ output = "%s", disabled = true })\n' "$(lua_escape "$monitor")" >"$lua_toggle"
        fi
        ;;
      internal-monitor-mirror)
        monitor_line=$(grep -E '^monitor=' "$conf_toggle" | head -n 1)
        external=$(printf '%s' "$monitor_line" | cut -d, -f1 | sed 's/^monitor=//')
        internal=$(printf '%s' "$monitor_line" | awk -F',[[:space:]]*mirror,[[:space:]]*' '{ print $2 }')
        if [[ -n $external && -n $internal ]]; then
          printf 'hl.monitor({ output = "%s", mode = "preferred", position = "auto", scale = 1, mirror = "%s" })\n' "$(lua_escape "$external")" "$(lua_escape "$internal")" >"$lua_toggle"
        fi
        ;;
      touchpad-disabled | touchscreen-disabled)
        device=$(sed -nE 's/^[[:space:]]*name[[:space:]]*=[[:space:]]*(.*)$/\1/p' "$conf_toggle" | head -n 1)
        if [[ -n $device ]]; then
          printf 'hl.device({ name = "%s", enabled = false })\n' "$(lua_escape "$device")" >"$lua_toggle"
        fi
        ;;
    esac
  fi

  mv "$conf_toggle" "$conf_toggle.bak.$timestamp"
done

sddm_hypr_conf="/usr/share/sddm/hyprland.conf"
sddm_hypr_lua="/usr/share/sddm/hyprland.lua"
sddm_wayland_conf="/etc/sddm.conf.d/10-wayland.conf"

if [[ -f $sddm_hypr_conf || -f $sddm_wayland_conf ]]; then
  if [[ -f $OMARCHY_PATH/default/sddm/hyprland.lua ]]; then
    sudo mkdir -p /usr/share/sddm
    sudo cp "$OMARCHY_PATH/default/sddm/hyprland.lua" "$sddm_hypr_lua"
  fi

  if [[ -f $sddm_wayland_conf ]]; then
    sudo sed -i 's|/usr/share/sddm/hyprland\.conf|/usr/share/sddm/hyprland.lua|g' "$sddm_wayland_conf"
  fi

  if [[ -f $sddm_hypr_conf ]]; then
    sudo mv "$sddm_hypr_conf" "$sddm_hypr_conf.bak.$timestamp"
  fi
fi

omarchy-state set reboot-required

echo "Hyprland must be restarted to switch from hyprland.conf to hyprland.lua. Log out and back in, or reboot when ready."
