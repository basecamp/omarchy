# Fix display issues on Dell XPS 2026+ with LG OLED panel and Intel Panther Lake (Xe3) GPU.
# Power-saving features cause the screen to run at 10hz.
if omarchy-hw-match "XPS" \
  && omarchy-hw-intel-ptl \
  && test "$(od -An -tx1 -j8 -N2 /sys/class/drm/card*-eDP-*/edid 2>/dev/null | tr -d ' \n')" = "30e4"; then

  echo "Detected Dell XPS with LG OLED panel on Panther Lake, applying display power-saving fix..."

  CMDLINE='KERNEL_CMDLINE[default]+=" xe.enable_panel_replay=0"'

  sudo mkdir -p /etc/limine-entry-tool.d
  cat <<EOF | sudo tee /etc/limine-entry-tool.d/dell-xps-ptl-display.conf >/dev/null
# Fix Dell XPS OLED display issues by disabling Xe PSR2 power-saving feature
$CMDLINE
EOF

  # Also append to /etc/default/limine if it exists, since it overrides drop-in configs
  if [ -f /etc/default/limine ] && ! grep -q 'xe.enable_panel_replay' /etc/default/limine; then
    echo "$CMDLINE" | sudo tee -a /etc/default/limine >/dev/null
  fi
fi
