echo "Move stock Hyprland user overrides into package defaults"

stock_input_sha="bf7602d679a31da028528d9b7dac64463217a9df42b254d3baefb7ce35674be5"
stock_bindings_sha="932d647b07d24907d46c0b7752bb81ad87276ccd057670be6c3a5c5e950c19aa"
plain_bindings_sha="5d92d4008b04848256445da3cf5c10422a8d537baad499a4e63f60daecaefc6f"

file_sha() {
  sha256sum "$1" | awk '{ print $1 }'
}

packaged_hypr_config() {
  local omarchy_config="$OMARCHY_PATH/config/hypr/$1"

  if [[ -f $omarchy_config ]]; then
    printf '%s\n' "$omarchy_config"
  else
    printf '/etc/skel/.config/hypr/%s\n' "$1"
  fi
}

replace_with_packaged_config() {
  local name="$1"
  local user_file="$HOME/.config/hypr/$name"
  local packaged_file

  packaged_file=$(packaged_hypr_config "$name")
  [[ -f $user_file && -f $packaged_file ]] || return 0

  cp "$packaged_file" "$user_file"
}

vconsole_value() {
  local key="$1"

  [[ -f /etc/vconsole.conf ]] || return 0

  awk -F= -v key="$key" '
    $1 == key {
      value = $2
      sub(/^[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      gsub(/^"/, "", value)
      gsub(/"$/, "", value)
      print value
      exit
    }
  ' /etc/vconsole.conf
}

active_lua_string_value() {
  local key="$1"
  local file="$2"

  awk -F= -v key="$key" '
    $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      value = $2
      sub(/^[[:space:]]*/, "", value)
      sub(/[[:space:]]*,?[[:space:]]*$/, "", value)
      gsub(/^"/, "", value)
      gsub(/"$/, "", value)
      print value
      exit
    }
  ' "$file"
}

normalized_input_sha() {
  sed \
    -e '/^[[:space:]]*kb_layout[[:space:]]*=/d' \
    -e '/^[[:space:]]*kb_variant[[:space:]]*=/d' \
    "$1" | sha256sum | awk '{ print $1 }'
}

input_is_stock_or_installer_synced() {
  local input_file="$1"
  local layout variant vconsole_layout vconsole_variant

  [[ $(normalized_input_sha "$input_file") == $stock_input_sha ]] || return 1

  layout=$(active_lua_string_value kb_layout "$input_file")
  variant=$(active_lua_string_value kb_variant "$input_file")
  vconsole_layout=$(vconsole_value XKBLAYOUT)
  vconsole_variant=$(vconsole_value XKBVARIANT)

  [[ -n $layout && $layout != $vconsole_layout ]] && return 1
  [[ -n $variant && $variant != $vconsole_variant ]] && return 1

  return 0
}

input_file="$HOME/.config/hypr/input.lua"
if [[ -f $input_file ]] && input_is_stock_or_installer_synced "$input_file"; then
  replace_with_packaged_config input.lua
fi

bindings_file="$HOME/.config/hypr/bindings.lua"
if [[ -f $bindings_file ]]; then
  case "$(file_sha "$bindings_file")" in
    "$stock_bindings_sha")
      replace_with_packaged_config bindings.lua
      ;;
    "$plain_bindings_sha")
      mkdir -p "$HOME/.local/state/omarchy"
      touch "$HOME/.local/state/omarchy/preinstalls-removed"
      replace_with_packaged_config bindings.lua
      ;;
  esac
fi

