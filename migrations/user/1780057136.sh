echo "Make Shift+Enter distinguishable for terminals and Codex"

alacritty_config="$HOME/.config/alacritty/alacritty.toml"
foot_config="$HOME/.config/foot/foot.ini"
ghostty_config="$HOME/.config/ghostty/config"
kitty_config="$HOME/.config/kitty/kitty.conf"

ensure_alacritty_shift_return() {
  local config="$1"

  [[ -f $config ]] || return 0

  if grep -q 'key = "Return", mods = "Shift", chars = "\\u001B\\r"' "$config"; then
    sed -i 's/{ key = "Return", mods = "Shift", chars = "\\u001B\\r" }/{ key = "Return", mods = "Shift", chars = "\\u001B[13;2u" }/' "$config"
  elif ! grep -q 'key = "Return", mods = "Shift", chars = "\\u001B\[13;2u"' "$config"; then
    if grep -qxF '{ key = "Return", mods = "Alt|Shift", chars = "\u001B[13;4u" }' "$config"; then
      sed -i '/^{ key = "Return", mods = "Alt|Shift", chars = "\\u001B\[13;4u" }$/i # Send Shift+Return as CSI-u so TUIs can distinguish it from Return without treating it as Alt+Return.\n{ key = "Return", mods = "Shift", chars = "\\u001B[13;2u" },' "$config"
    elif grep -qxF '{ key = "Insert", mods = "Control", action = "Copy" },' "$config"; then
      sed -i '/^{ key = "Insert", mods = "Control", action = "Copy" },$/a # Send Shift+Return as CSI-u so TUIs can distinguish it from Return without treating it as Alt+Return.\n{ key = "Return", mods = "Shift", chars = "\\u001B[13;2u" },' "$config"
    else
      printf '\n# Send Shift+Return as CSI-u so TUIs can distinguish it from Return without treating it as Alt+Return.\n{ key = "Return", mods = "Shift", chars = "\\u001B[13;2u" }\n' >>"$config"
    fi
  fi
}

ensure_ghostty_binding() {
  local config="$1"
  local key="$2"
  local binding="$3"
  local comment="$4"
  local key_regex

  [[ -f $config ]] || return 0

  key_regex=$(printf '%s\n' "$key" | sed 's/[][\\.^$*+?{}|()\/]/\\&/g')

  if grep -Eq "^keybind = $key_regex=.*13;[24]u" "$config"; then
    sed -i "s/^keybind = $key_regex=.*/keybind = $key=$binding/" "$config"
  elif ! grep -qF "keybind = $key=" "$config"; then
    if grep -qxF 'keybind = control+insert=copy_to_clipboard' "$config"; then
      sed -i "/^keybind = control+insert=copy_to_clipboard$/a $comment\nkeybind = $key=$binding" "$config"
    else
      printf '\n%s\nkeybind = %s=%s\n' "$comment" "$key" "$binding" >>"$config"
    fi
  fi
}

ensure_kitty_binding() {
  local config="$1"
  local key="$2"
  local binding="$3"
  local comment="$4"
  local key_regex
  local tmp

  [[ -f $config ]] || return 0

  key_regex=$(printf '%s\n' "$key" | sed 's/[][\\.^$*+?{}|()\/]/\\&/g')

  if grep -Eq "^map[[:space:]]+$key_regex[[:space:]].*13;[24]u" "$config"; then
    tmp=$(mktemp)
    KEY="$key" BINDING="$binding" awk '
      BEGIN {
        key = ENVIRON["KEY"]
        binding = ENVIRON["BINDING"]
      }
      {
        split($0, parts, /[[:space:]]+/)
        if (parts[1] == "map" && parts[2] == key && $0 ~ /13;[24]u/) {
          $0 = "map " key " " binding
        }
        print
      }
    ' "$config" >"$tmp" && mv "$tmp" "$config"
  elif ! grep -Eq "^map[[:space:]]+$key_regex[[:space:]]" "$config"; then
    if grep -qxF 'map shift+insert paste_from_clipboard' "$config"; then
      tmp=$(mktemp)
      KEY="$key" BINDING="$binding" COMMENT="$comment" awk '
        BEGIN {
          key = ENVIRON["KEY"]
          binding = ENVIRON["BINDING"]
          comment = ENVIRON["COMMENT"]
        }
        { print }
        !inserted && $0 == "map shift+insert paste_from_clipboard" {
          print comment
          print "map " key " " binding
          inserted = 1
        }
      ' "$config" >"$tmp" && mv "$tmp" "$config"
    else
      printf '\n%s\nmap %s %s\n' "$comment" "$key" "$binding" >>"$config"
    fi
  fi
}

ensure_foot_text_binding() {
  local config="$1"
  local sequence="$2"
  local binding="$3"
  local comment="$4"
  local tmp

  [[ -f $config ]] || return 0

  if grep -qF "$sequence=" "$config"; then
    tmp=$(mktemp)
    SEQUENCE="$sequence" BINDING="$binding" awk '
      BEGIN {
        sequence = ENVIRON["SEQUENCE"]
        binding = ENVIRON["BINDING"]
      }
      index($0, sequence "=") == 1 { $0 = sequence "=" binding }
      { print }
    ' "$config" >"$tmp" && mv "$tmp" "$config"
  elif grep -qxF '[text-bindings]' "$config"; then
    tmp=$(mktemp)
    SEQUENCE="$sequence" BINDING="$binding" COMMENT="$comment" awk '
      BEGIN {
        sequence = ENVIRON["SEQUENCE"]
        binding = ENVIRON["BINDING"]
        comment = ENVIRON["COMMENT"]
      }
      { print }
      !inserted && $0 == "[text-bindings]" {
        print comment
        print sequence "=" binding
        inserted = 1
      }
    ' "$config" >"$tmp" && mv "$tmp" "$config"
  else
    printf '\n[text-bindings]\n%s\n%s=%s\n' "$comment" "$sequence" "$binding" >>"$config"
  fi
}

ensure_alacritty_shift_return "$alacritty_config"

ensure_ghostty_binding \
  "$ghostty_config" \
  "shift+enter" \
  "csi:13;2u" \
  "# Send Shift+Enter as CSI-u so TUIs can distinguish it from Enter."

ensure_ghostty_binding \
  "$ghostty_config" \
  "alt+shift+enter" \
  "csi:13;4u" \
  "# Legacy encoding sends Alt+Shift+Enter the same as Alt+Enter; send CSI-u so tmux can match M-S-Enter."

ensure_kitty_binding \
  "$kitty_config" \
  "shift+enter" \
  "send_text all \\e[13;2u" \
  "# Send Shift+Enter as CSI-u so TUIs can distinguish it from Enter."

ensure_kitty_binding \
  "$kitty_config" \
  "alt+shift+enter" \
  "send_text all \\e[13;4u" \
  "# Kitty legacy encoding sends Alt+Shift+Enter the same as Alt+Enter; send CSI-u so tmux can match M-S-Enter."

ensure_foot_text_binding \
  "$foot_config" \
  "\\x1b[13;2u" \
  "Shift+Return" \
  "# Send Shift+Return as CSI-u so TUIs can distinguish it from Return."

ensure_foot_text_binding \
  "$foot_config" \
  "\\x1b[13;4u" \
  "Mod1+Shift+Return" \
  "# Send Alt+Shift+Return as CSI-u so tmux can match M-S-Enter."
