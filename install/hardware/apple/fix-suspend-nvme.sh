# Fix NVMe suspend issues on MacBook models
# This prevents NVMe drives from failing to wake from sleep properly
MACBOOK_MODEL=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)

if [[ $MACBOOK_MODEL =~ MacBook(8,1|9,1|10,1)|MacBookPro13,[123]|MacBookPro14,[123] ]]; then
  echo "Detected MacBook model: $MACBOOK_MODEL"

  # Prefer the real NVMe function. On 15" 2016–2017 machines 01:00.0 is
  # the Radeon, not the disk (Samsung is 02:00.0 on MacBookPro14,3).
  NVME_DEVICE=""
  if [[ -e /sys/class/nvme/nvme0/device/d3cold_allowed ]]; then
    NVME_DEVICE=$(readlink -f /sys/class/nvme/nvme0/device)/d3cold_allowed
  elif [[ -f /sys/bus/pci/devices/0000:01:00.0/d3cold_allowed ]]; then
    NVME_DEVICE=/sys/bus/pci/devices/0000:01:00.0/d3cold_allowed
  fi

  if [[ -n $NVME_DEVICE && -f $NVME_DEVICE ]]; then
    echo "Applying NVMe suspend fix at $NVME_DEVICE"

    sudo mkdir -p /etc/systemd/system
    sudo tee /etc/systemd/system/omarchy-nvme-suspend-fix.service >/dev/null <<EOF
[Unit]
Description=Omarchy NVMe Suspend Fix for MacBook

[Service]
ExecStart=/bin/bash -c 'echo 0 > $NVME_DEVICE'

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl enable omarchy-nvme-suspend-fix.service
  else
    echo "Warning: NVMe d3cold_allowed not found"
    echo "This fix may not be needed for this MacBook model"
  fi
fi
