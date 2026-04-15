# Fix display issues on Dell XPS Panther Lake (Xe3) systems.
# Xe PSR causes freezes and display glitches on both OLED and IPS panels.
# LG OLED panels also need Panel Replay disabled.
if omarchy-hw-match "XPS" && omarchy-hw-intel-ptl; then
  echo "Detected Dell XPS on Panther Lake, applying display power-saving fixes..."

  CMDLINE='KERNEL_CMDLINE[default]+=" xe.enable_psr=0"'
  COMMENT='Disable Xe PSR on Dell XPS Panther Lake systems'

  if omarchy-hw-dell-xps-oled; then
    CMDLINE='KERNEL_CMDLINE[default]+=" xe.enable_psr=0 xe.enable_panel_replay=0"'
    COMMENT='Disable Xe PSR and Panel Replay on Dell XPS Panther Lake OLED systems'
  fi

  sudo mkdir -p /etc/limine-entry-tool.d
  cat <<EOF | sudo tee /etc/limine-entry-tool.d/dell-xps-ptl-display.conf >/dev/null
# $COMMENT
$CMDLINE
EOF

  # Also append to /etc/default/limine if it exists, since it overrides drop-in configs
  if [[ -f /etc/default/limine ]]; then
    if ! grep -Fq 'xe.enable_psr' /etc/default/limine; then
      echo 'KERNEL_CMDLINE[default]+=" xe.enable_psr=0"' | sudo tee -a /etc/default/limine >/dev/null
    fi

    if omarchy-hw-dell-xps-oled && ! grep -Fq 'xe.enable_panel_replay' /etc/default/limine; then
      echo 'KERNEL_CMDLINE[default]+=" xe.enable_panel_replay=0"' | sudo tee -a /etc/default/limine >/dev/null
    fi
  fi
fi
