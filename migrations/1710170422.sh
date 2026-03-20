echo "Disable hardware cursors in Hyprland to fix night light (issue #4973)"

if [[ -f ~/.config/hypr/looknfeel.conf ]]; then
  if grep -qE '^[[:space:]]*no_hardware_cursors[[:space:]]*=' ~/.config/hypr/looknfeel.conf; then
if [[ ! -f ~/.config/hypr/looknfeel.conf ]]; then
  echo "Error: ~/.config/hypr/looknfeel.conf does not exist yet; rerun this migration after it has been created." >&2
  exit 1
fi

if ! grep -q "no_hardware_cursors" ~/.config/hypr/looknfeel.conf; then
  sed -i '/cursor {/a \    no_hardware_cursors = true' ~/.config/hypr/looknfeel.conf
fi
