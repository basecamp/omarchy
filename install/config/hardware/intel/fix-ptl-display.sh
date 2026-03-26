# Fix display issues on Intel Panther Lake (Xe3) GPUs by disabling power-saving
# features that cause screen to run at 10hz (e.g. Dell XPS 2026).
if omarchy-hw-intel-ptl; then
  echo "Detected Intel Panther Lake GPU, applying display fixes..."

  PANTHER_LAKE_CMDLINE='KERNEL_CMDLINE[default]+=" xe.enable_psr=0 xe.enable_panel_replay=0 xe.enable_fbc=0 xe.enable_dc=0"'

  sudo mkdir -p /etc/limine-entry-tool.d
  cat <<EOF | sudo tee /etc/limine-entry-tool.d/intel-panther-lake-display.conf >/dev/null
# Fix Panther Lake display issues by disabling Xe power-saving features
$PANTHER_LAKE_CMDLINE
EOF

  # Also append to /etc/default/limine if it exists, since it overrides drop-in configs
  if [ -f /etc/default/limine ] && ! grep -q 'xe.enable_psr' /etc/default/limine; then
    echo "$PANTHER_LAKE_CMDLINE" | sudo tee -a /etc/default/limine >/dev/null
  fi
fi
