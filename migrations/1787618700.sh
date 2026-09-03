echo "Store Hyprland input-device names as data instead of generated Lua"

# omarchy-toggle-input-device used to interpolate hyprctl device names into
# hyprctl eval and a generated Lua file. Those names come from USB descriptors,
# so recover the plain device name as data and delete the generated Lua. A name
# that could have broken out of the old Lua string literal is discarded, not
# trusted. The old script wrote to ~/.local/state regardless of XDG_STATE_HOME.
toggles_dir="$HOME/.local/state/omarchy/toggles/hypr"

reapply=0

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

  if [[ -f $name_file ]]; then
    reapply=1
  fi
done

# The package hook reloads Hyprland before migrations run, so this session has
# already dropped the disable: the generated Lua is no longer loaded and the
# name file did not exist yet to replace it. Reload once more now that it does,
# or the device the user switched off stays on until their next login.
if (( reapply )); then
  hyprctl reload >/dev/null 2>&1 || true
fi
