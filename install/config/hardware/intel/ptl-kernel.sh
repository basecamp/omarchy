# Install Panther Lake kernel for Intel Panther Lake systems
# The linux-ptl kernel includes audio driver patches not yet in mainline.

if omarchy-hw-intel-ptl; then
  echo "Detected Intel Panther Lake, installing PTL kernel..."

  omarchy-pkg-add linux-ptl linux-ptl-headers
  for pkg in linux linux-headers; do
    sudo pacman -Rdd --noconfirm "$pkg" 2>/dev/null || true
  done

  sudo mkdir -p /etc/limine-entry-tool.d
  cat <<EOF | sudo tee /etc/limine-entry-tool.d/intel-panther-lake.conf >/dev/null
# Only show Panther Lake kernel in boot menu
BOOT_ORDER="linux-ptl*, *fallback, Snapshots"
EOF
fi
