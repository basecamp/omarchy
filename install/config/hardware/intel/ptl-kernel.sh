# Install Panther Lake kernel for Intel Panther Lake systems
# The linux-ptl kernel includes audio driver patches not yet in mainline.

if omarchy-hw-intel-ptl; then
  echo "Detected Intel Panther Lake, installing PTL kernel..."

  omarchy-pkg-add linux-ptl linux-ptl-headers

  sudo mkdir -p /etc/limine-entry-tool.d
  cat <<EOF | sudo tee /etc/limine-entry-tool.d/intel-panther-lake.conf >/dev/null
# Prioritize Panther Lake kernel as the default boot entry
BOOT_ORDER="linux-ptl*, *, *fallback, Snapshots"
EOF

  # Make the PTL kernel the default boot entry in limine with auto-boot
  sed -i 's/^default_entry: 2/default_entry: 1/' $OMARCHY_PATH/default/limine/limine.conf
  sed -i 's/^#timeout: 3/timeout: 3/' $OMARCHY_PATH/default/limine/limine.conf
fi
