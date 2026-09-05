echo "Backfill hardware support and tmux settings added before Omarchy quattro"

tmux_config="$HOME/.config/tmux/tmux.conf"
if [[ -f $tmux_config ]]; then
  # Nix/home-manager and other declarative setups keep tmux.conf read-only
  # (often a symlink into a store). `sed -i` under `bash -euo pipefail` would
  # abort this whole migration — including the hardware package installs below —
  # and leave omarchy-migrate retrying forever. Rewrite via a temp file and write
  # through the path (same pattern as migrations/1785189600.sh) so a symlink
  # keeps its target; if the write is refused, skip and continue.
  tmux_tmp=$(mktemp)
  if sed 's/^set -g terminal-features\[3\] "xterm-kitty:extkeys"$/set -ag terminal-features "xterm-kitty:extkeys"/' \
    "$tmux_config" >"$tmux_tmp" &&
    { grep -q 'M-S-Enter' "$tmux_tmp" ||
      sed '/^# Pane Controls$/a\bind -n M-Enter split-window -v -c "#{pane_current_path}"\nbind -n M-S-Enter split-window -h -c "#{pane_current_path}"\nbind -n M-Escape kill-pane\n' \
        "$tmux_tmp" >"${tmux_tmp}.next" && mv "${tmux_tmp}.next" "$tmux_tmp"; } &&
    cat "$tmux_tmp" >"$tmux_config"; then
    omarchy-restart-tmux
  else
    echo "Skipping tmux.conf edits: could not write $tmux_config (managed outside Omarchy?)."
  fi
  rm -f "$tmux_tmp" "${tmux_tmp}.next"
fi

hardware_packages=()
if lspci | grep -iE '(Multimedia audio controller|Audio device).*Intel' >/dev/null && omarchy-pkg-missing sof-firmware; then
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
