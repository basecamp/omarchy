# Fix display issues on Intel Panther Lake (Xe3) GPUs by disabling power-saving
# features that cause screen to run at 10hz (e.g. Dell XPS 2026).
if lspci | grep -iE 'vga|3d|display' | grep -qi 'panther lake'; then
  echo "Detected Intel Panther Lake GPU, applying display fixes..."

  sudo mkdir -p /etc/limine-entry-tool.d
  cat <<EOF | sudo tee /etc/limine-entry-tool.d/intel-panther-lake-display.conf >/dev/null
# Fix Panther Lake display issues by disabling Xe power-saving features
KERNEL_CMDLINE[default]+=" xe.enable_psr=0 xe.enable_panel_replay=0 xe.enable_fbc=0 xe.enable_dc=0"
EOF
fi
