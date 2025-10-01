# Fix NVMe suspend issues on MacBook models
# This prevents NVMe drives from failing to wake from sleep properly
MACBOOK_MODEL=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)

if [[ "$MACBOOK_MODEL" =~ MacBook(8,1|9,1|10,1)|MacBookPro13,[123]|MacBookPro14,[123] ]]; then
  echo "Detected MacBook model: $MACBOOK_MODEL"
  echo "Applying NVMe suspend fix..."

  # Check if the NVMe device exists at the expected PCI address
  NVME_DEVICE="/sys/bus/pci/devices/0000:01:00.0/d3cold_allowed"

  if [[ -f "$NVME_DEVICE" ]]; then
    # Apply the fix immediately to prevent d3cold power state issues
    echo 0 | sudo tee "$NVME_DEVICE" >/dev/null || true

    # Create systemd service to ensure fix persists across reboots
    # The service runs after multi-user.target to ensure the device is available
    cat <<EOF | sudo tee /etc/systemd/system/omarchy-nvme-suspend-fix.service >/dev/null
[Unit]
Description=Omarchy NVMe Suspend Fix for MacBook

[Service]
ExecStart=/bin/bash -c 'echo 0 > /sys/bus/pci/devices/0000\:01\:00.0/d3cold_allowed'

[Install]
WantedBy=multi-user.target
EOF

    # Enable the service to run on boot
    sudo systemctl enable omarchy-nvme-suspend-fix.service
    sudo systemctl daemon-reload

    echo "NVMe suspend fix applied and systemd service enabled"
  else
    echo "Warning: NVMe device not found at expected PCI address (0000:01:00.0)"
    echo "This fix may not be needed for this MacBook model"
  fi
fi
