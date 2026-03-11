echo "Disable hardware cursors in Hyprland to fix night light (issue #4973)"

if [[ -f ~/.config/hypr/looknfeel.conf ]]; then
  if ! grep -q "no_hardware_cursors" ~/.config/hypr/looknfeel.conf; then
    sed -i '/cursor {/a \    no_hardware_cursors = true' ~/.config/hypr/looknfeel.conf
  fi
fi
