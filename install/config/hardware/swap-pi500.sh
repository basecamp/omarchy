# Configure swap file for Raspberry Pi 500 and newer
# These devices have 16GB+ RAM but benefit from swap as a safety net

if [[ ! -f /sys/firmware/devicetree/base/model ]]; then
  exit 0
fi

model=$(tr -d '\0' < /sys/firmware/devicetree/base/model)

if [[ "$model" == *"Raspberry Pi 500"* ]] || [[ "$model" == *"Raspberry Pi 5"* ]]; then
  echo "Raspberry Pi 5/500 detected: configuring 8GB swap file"

  # Detect filesystem type for root partition
  root_fstype=$(findmnt -n -o FSTYPE /)

  if [[ ! -f /swapfile ]]; then
    if [[ "$root_fstype" == "btrfs" ]]; then
      # Btrfs requires special handling: NOCOW attribute before allocation
      echo "  - Btrfs detected: creating swap file with NOCOW attribute"
      sudo truncate -s 0 /swapfile
      sudo chattr +C /swapfile
      sudo btrfs property set /swapfile compression none 2>/dev/null || true
      sudo fallocate -l 8G /swapfile
    else
      # Standard filesystem (ext4, etc.)
      sudo fallocate -l 8G /swapfile
    fi
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    echo "  - Created 8GB swap file"
  else
    # Swap file exists - check if it needs NOCOW fix for Btrfs
    if [[ "$root_fstype" == "btrfs" ]]; then
      # Check if swap is working
      if ! swapon --show | grep -q /swapfile; then
        echo "  - Existing swap file may need NOCOW fix for Btrfs, recreating..."
        sudo swapoff /swapfile 2>/dev/null || true
        sudo rm -f /swapfile
        sudo truncate -s 0 /swapfile
        sudo chattr +C /swapfile
        sudo btrfs property set /swapfile compression none 2>/dev/null || true
        sudo fallocate -l 8G /swapfile
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        echo "  - Recreated 8GB swap file with NOCOW attribute"
      fi
    fi
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
