echo "Add easier tmux pane controls with Alt+Enter splits and CSI-u Shift+Enter across terminals"

# tmux: add M-Enter/M-S-Enter/M-Escape pane bindings and enable extkeys for kitty terminal
tmux_config="$HOME/.config/tmux/tmux.conf"
if [[ -f $tmux_config ]]; then
  if ! grep -q "M-S-Enter" "$tmux_config"; then
    sed -i '/^# Pane Controls$/a\bind -n M-Enter split-window -v -c "#{pane_current_path}"\nbind -n M-S-Enter split-window -h -c "#{pane_current_path}"\nbind -n M-Escape kill-pane\n' "$tmux_config"
  fi

  if ! grep -q "xterm-kitty:extkeys" "$tmux_config"; then
    sed -i '/^set -g extended-keys-format csi-u$/a\set -ag terminal-features "xterm-kitty:extkeys"' "$tmux_config"
  fi

  omarchy-restart-tmux
fi

# alacritty: replace the old Shift+Return binding with CSI-u encodings
alacritty_config="$HOME/.config/alacritty/alacritty.toml"
if [[ -f $alacritty_config ]] && ! grep -q '13;2u' "$alacritty_config"; then
  sed -i -E 's|^([[:space:]]*).*chars = "\\u001B\\r".*|\1# Send Shift+Return as CSI-u so TUIs can distinguish it from Return without treating it as Alt+Return.\n\1{ key = "Return", mods = "Shift", chars = "\\u001B[13;2u" },\n\1# Legacy encoding sends Alt+Shift+Return the same as Alt+Return; send CSI-u so tmux can match M-S-Enter.\n\1{ key = "Return", mods = "Alt\|Shift", chars = "\\u001B[13;4u" }|' "$alacritty_config"
fi

# foot: add CSI-u text bindings for Shift+Return and Alt+Shift+Return
foot_config="$HOME/.config/foot/foot.ini"
if [[ -f $foot_config ]]; then
  if ! grep -q '^\[text-bindings\]$' "$foot_config"; then
    printf '\n[text-bindings]\n' >> "$foot_config"
  fi

  if ! grep -Fq '\x1b[13;4u=Mod1+Shift+Return' "$foot_config"; then
    sed -i '/^\[text-bindings\]$/a\# Send Alt+Shift+Return as CSI-u so tmux can match M-S-Enter.\n\\x1b[13;4u=Mod1+Shift+Return' "$foot_config"
  fi

  if ! grep -Fq '\x1b[13;2u=Shift+Return' "$foot_config"; then
    sed -i '/^\[text-bindings\]$/a\# Send Shift+Return as CSI-u so TUIs can distinguish it from Return.\n\\x1b[13;2u=Shift+Return' "$foot_config"
  fi
fi

# ghostty: add CSI-u keybinds for Shift+Enter and Alt+Shift+Enter
ghostty_config="$HOME/.config/ghostty/config"
if [[ -f $ghostty_config ]] && ! grep -q 'csi:13;2u' "$ghostty_config"; then
  sed -i '/^keybind = control+insert=copy_to_clipboard$/a\# Send Shift+Enter as CSI-u so TUIs can distinguish it from Enter.\nkeybind = shift+enter=csi:13;2u\n# Legacy encoding sends Alt+Shift+Enter the same as Alt+Enter; send CSI-u so tmux can match M-S-Enter.\nkeybind = alt+shift+enter=csi:13;4u' "$ghostty_config"
fi

# kitty: add CSI-u key mappings for Shift+Enter and Alt+Shift+Enter
kitty_config="$HOME/.config/kitty/kitty.conf"
if [[ -f $kitty_config ]] && ! grep -q '13;2u' "$kitty_config"; then
  sed -i '/^map shift+insert paste_from_clipboard$/a\# Send Shift+Enter as CSI-u so TUIs can distinguish it from Enter.\nmap shift+enter send_text all \\e[13;2u\n# Kitty legacy encoding sends Alt+Shift+Enter the same as Alt+Enter; send CSI-u so tmux can match M-S-Enter.\nmap alt+shift+enter send_text all \\e[13;4u' "$kitty_config"
fi
