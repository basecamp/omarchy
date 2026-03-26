# Fix display issues on Dell XPS 2026+ with LG OLED panel and Intel Panther Lake (Xe3) GPU.
# Power-saving features cause the screen to run at 10hz.
if omarchy-hw-match "XPS" \
  && omarchy-hw-intel-ptl \
  && grep -rqi "LG" /sys/class/drm/card*-eDP-*/edid 2>/dev/null; then

  echo "Detected Dell XPS with LG OLED panel on Panther Lake, applying display fixes..."

  CMDLINE='KERNEL_CMDLINE[default]+=" xe.enable_psr=0 xe.enable_panel_replay=0 xe.enable_fbc=0 xe.enable_dc=0"'

  sudo mkdir -p /etc/limine-entry-tool.d
  cat <<EOF | sudo tee /etc/limine-entry-tool.d/dell-xps-ptl-display.conf >/dev/null
# Fix Dell XPS OLED display issues by disabling Xe power-saving features
$CMDLINE
EOF

  # Also append to /etc/default/limine if it exists, since it overrides drop-in configs
  if [ -f /etc/default/limine ] && ! grep -q 'xe.enable_psr' /etc/default/limine; then
    echo "$CMDLINE" | sudo tee -a /etc/default/limine >/dev/null
  fi
fi
