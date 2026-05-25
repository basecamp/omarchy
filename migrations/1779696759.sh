echo "Make Alt+Shift+Enter distinguishable for terminals and tmux"

alacritty_config="$HOME/.config/alacritty/alacritty.toml"
ghostty_config="$HOME/.config/ghostty/config"
kitty_config="$HOME/.config/kitty/kitty.conf"
tmux_config="$HOME/.config/tmux/tmux.conf"

tmux_changed=0

if [[ -f $alacritty_config ]] && ! grep -q '13;4u' "$alacritty_config"; then
  if grep -q 'key = "Return", mods = "Shift", chars = "\\u001B\\r"' "$alacritty_config"; then
    sed -i '/key = "Return", mods = "Shift", chars = "\\u001B\\r"/s/ }$/ },/' "$alacritty_config"
    sed -i '/key = "Return", mods = "Shift", chars = "\\u001B\\r"/a # Legacy encoding sends Alt+Shift+Return the same as Alt+Return; send CSI-u so tmux can match M-S-Enter.\n{ key = "Return", mods = "Alt|Shift", chars = "\\u001B[13;4u" }' "$alacritty_config"
  elif grep -q 'key = "Insert", mods = "Control", action = "Copy"' "$alacritty_config"; then
    sed -i '/key = "Insert", mods = "Control", action = "Copy"/a # Legacy encoding sends Alt+Shift+Return the same as Alt+Return; send CSI-u so tmux can match M-S-Enter.\n{ key = "Return", mods = "Alt|Shift", chars = "\\u001B[13;4u" },' "$alacritty_config"
  fi
fi

if [[ -f $ghostty_config ]] && ! grep -q 'alt+shift+enter=.*13;4u' "$ghostty_config"; then
  if grep -qxF 'keybind = control+insert=copy_to_clipboard' "$ghostty_config"; then
    sed -i '/^keybind = control+insert=copy_to_clipboard$/a # Legacy encoding sends Alt+Shift+Enter the same as Alt+Enter; send CSI-u so tmux can match M-S-Enter.\nkeybind = alt+shift+enter=csi:13;4u' "$ghostty_config"
  else
    printf '\n# Legacy encoding sends Alt+Shift+Enter the same as Alt+Enter; send CSI-u so tmux can match M-S-Enter.\nkeybind = alt+shift+enter=csi:13;4u\n' >>"$ghostty_config"
  fi
fi

if [[ -f $kitty_config ]] && ! grep -Eq '^map[[:space:]]+alt\+shift\+enter[[:space:]]' "$kitty_config"; then
  if grep -qxF 'map shift+insert paste_from_clipboard' "$kitty_config"; then
    sed -i '/^map shift+insert paste_from_clipboard$/a # Kitty legacy encoding sends Alt+Shift+Enter the same as Alt+Enter; send CSI-u so tmux can match M-S-Enter.\nmap alt+shift+enter send_text all \\e[13;4u' "$kitty_config"
  else
    printf '\n# Kitty legacy encoding sends Alt+Shift+Enter the same as Alt+Enter; send CSI-u so tmux can match M-S-Enter.\nmap alt+shift+enter send_text all \\e[13;4u\n' >>"$kitty_config"
  fi
fi

if [[ -f $tmux_config ]] && grep -qxF "set -as terminal-features ',xterm-kitty:extkeys'" "$tmux_config"; then
  sed -i 's/^set -as terminal-features '"'"',xterm-kitty:extkeys'"'"'$/set -g terminal-features[3] "xterm-kitty:extkeys"/' "$tmux_config"
  tmux_changed=1
elif [[ -f $tmux_config ]] && ! grep -q 'xterm-kitty:extkeys' "$tmux_config" && ! grep -Eq '^(set|set-option)[[:space:]].*terminal-features' "$tmux_config"; then
  if grep -qxF 'set -g extended-keys-format csi-u' "$tmux_config"; then
    sed -i '/^set -g extended-keys-format csi-u$/a set -g terminal-features[3] "xterm-kitty:extkeys"' "$tmux_config"
  else
    printf '\nset -g terminal-features[3] "xterm-kitty:extkeys"\n' >>"$tmux_config"
  fi

  tmux_changed=1
fi

if (( tmux_changed )); then
  omarchy-restart-tmux
fi
