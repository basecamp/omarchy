# Install Panther Lake audio kernel for Intel Panther Lake systems
# The linux-ptl-audio kernel includes audio driver patches not yet in mainline.
if omarchy-hw-intel-ptl; then
  echo "Detected Intel Panther Lake, installing PTL audio kernel..."

  omarchy-pkg-add linux-ptl-audio linux-ptl-audio-headers

  sudo mkdir -p /etc/limine-entry-tool.d
  cat <<EOF | sudo tee /etc/limine-entry-tool.d/intel-panther-lake-audio.conf >/dev/null
# Prioritize Panther Lake audio kernel as the default boot entry
BOOT_ORDER="linux-ptl-audio*, *, *fallback, Snapshots"
EOF

  # Make the PTL audio kernel the default boot entry in limine
  sed -i 's/^default_entry: 2/default_entry: 1/' $OMARCHY_PATH/default/limine/limine.conf
fi
