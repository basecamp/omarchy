echo "Make Alt+Shift+Enter distinguishable for Kitty and tmux"

kitty_config="$HOME/.config/kitty/kitty.conf"
tmux_config="$HOME/.config/tmux/tmux.conf"

if [[ -f $kitty_config ]] && ! grep -Eq '^map[[:space:]]+alt\+shift\+enter[[:space:]]' "$kitty_config"; then
  if grep -qxF 'map shift+insert paste_from_clipboard' "$kitty_config"; then
    sed -i '/^map shift+insert paste_from_clipboard$/a # Kitty legacy encoding sends Alt+Shift+Enter the same as Alt+Enter; send CSI-u so tmux can match M-S-Enter.\nmap alt+shift+enter send_text all \\e[13;4u' "$kitty_config"
  else
    printf '\n# Kitty legacy encoding sends Alt+Shift+Enter the same as Alt+Enter; send CSI-u so tmux can match M-S-Enter.\nmap alt+shift+enter send_text all \\e[13;4u\n' >>"$kitty_config"
  fi
fi

if [[ -f $tmux_config ]] && grep -qxF "set -as terminal-features ',xterm-kitty:extkeys'" "$tmux_config"; then
  sed -i 's/^set -as terminal-features '"'"',xterm-kitty:extkeys'"'"'$/set -g terminal-features[3] "xterm-kitty:extkeys"/' "$tmux_config"
elif [[ -f $tmux_config ]] && ! grep -q 'xterm-kitty:extkeys' "$tmux_config" && ! grep -Eq '^(set|set-option)[[:space:]].*terminal-features' "$tmux_config"; then
  if grep -qxF 'set -g extended-keys-format csi-u' "$tmux_config"; then
    sed -i '/^set -g extended-keys-format csi-u$/a set -g terminal-features[3] "xterm-kitty:extkeys"' "$tmux_config"
  else
    printf '\nset -g terminal-features[3] "xterm-kitty:extkeys"\n' >>"$tmux_config"
  fi
fi
