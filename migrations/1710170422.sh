echo "Disable hardware cursors in Hyprland to fix night light (issue #4973)"

if [[ -f ~/.config/hypr/looknfeel.conf ]]; then
  if grep -qE '^[[:space:]]*no_hardware_cursors[[:space:]]*=' ~/.config/hypr/looknfeel.conf; then
    sed -i -E 's/^[[:space:]]*no_hardware_cursors[[:space:]]*=.*/    no_hardware_cursors = true/' ~/.config/hypr/looknfeel.conf
  else
    sed -i '/cursor {/a\    no_hardware_cursors = true' ~/.config/hypr/looknfeel.conf
  fi
fi
