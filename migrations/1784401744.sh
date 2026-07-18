echo "Backfill hardware support and tmux settings added before Omarchy quattro"

tmux_config="$HOME/.config/tmux/tmux.conf"
if [[ -f $tmux_config ]]; then
  sed -i 's/^set -g terminal-features\[3\] "xterm-kitty:extkeys"$/set -ag terminal-features "xterm-kitty:extkeys"/' "$tmux_config"

  if ! grep -q 'M-S-Enter' "$tmux_config"; then
    sed -i '/^# Pane Controls$/a\bind -n M-Enter split-window -v -c "#{pane_current_path}"\nbind -n M-S-Enter split-window -h -c "#{pane_current_path}"\nbind -n M-Escape kill-pane\n' "$tmux_config"
  fi

  omarchy-restart-tmux
fi

hardware_packages=()
if lspci | grep -qiE '(Multimedia audio controller|Audio device).*Intel' && omarchy-pkg-missing sof-firmware; then
  hardware_packages+=(sof-firmware)
fi
if lspci | grep -iE '(VGA|Display).*Intel' >/dev/null && omarchy-pkg-missing vulkan-intel; then
  hardware_packages+=(vulkan-intel)
fi
if lspci | grep -iE '(VGA|Display).*AMD' >/dev/null && omarchy-pkg-missing vulkan-radeon; then
  hardware_packages+=(vulkan-radeon)
fi
if lspci | grep -iE '(VGA|Display).*Apple' >/dev/null && omarchy-pkg-missing vulkan-asahi; then
  hardware_packages+=(vulkan-asahi)
fi

if (( ${#hardware_packages[@]} > 0 )); then
  omarchy-pkg-add "${hardware_packages[@]}"
  omarchy-state set reboot-required
fi

if omarchy-hw-match "DX13260"; then
  gsettings set org.gnome.desktop.interface text-scaling-factor 0.95
fi
