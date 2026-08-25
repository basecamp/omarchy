echo "Store Hyprland input-device names as data instead of generated Lua"

# omarchy-toggle-input-device used to interpolate hyprctl device names into
# hyprctl eval and a generated Lua file. Those names come from USB descriptors,
# so recover the plain device name as data and delete the generated Lua. A name
# that could have broken out of the old Lua string literal is discarded, not
# trusted. The old script wrote to ~/.local/state regardless of XDG_STATE_HOME.
toggles_dir="$HOME/.local/state/omarchy/toggles/hypr"

for kind in touchpad touchscreen; do
  state_file="$toggles_dir/$kind-disabled.lua"
  name_file="$toggles_dir/$kind-disabled-name"

  [[ -f $state_file ]] || continue

  if [[ ! -f $name_file && -r $state_file ]]; then
    old=$(<"$state_file")
    pattern='^hl\.device\(\{ name = "([^"\\[:cntrl:]]+)", enabled = false \}\)$'
    if [[ $old =~ $pattern ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}" >"$name_file"
    fi
  fi

  rm -f "$state_file"
done
