# Configure swap file for Raspberry Pi 500 and newer
# These devices have 16GB+ RAM but benefit from swap as a safety net

if [[ ! -f /sys/firmware/devicetree/base/model ]]; then
  exit 0
fi

model=$(tr -d '\0' < /sys/firmware/devicetree/base/model)

if [[ "$model" == *"Raspberry Pi 500"* ]]; then
  echo "Raspberry Pi 500 detected: configuring 8GB swap file"

  if [[ ! -f /swapfile ]]; then
    sudo fallocate -l 8G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    echo "  - Created 8GB swap file"
  fi

  if ! swapon --show | grep -q /swapfile; then
    sudo swapon /swapfile
    echo "  - Enabled swap"
  fi

  if ! grep -q "^/swapfile" /etc/fstab; then
    echo '/swapfile none swap defaults 0 0' | sudo tee -a /etc/fstab >/dev/null
    echo "  - Added swap to fstab"
  fi

  if [[ ! -f /etc/sysctl.d/99-swappiness.conf ]]; then
    echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf >/dev/null
    echo "  - Set swappiness to 10"
  fi
fi
