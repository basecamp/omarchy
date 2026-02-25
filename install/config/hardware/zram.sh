# Configure zram-based compressed swap for all ARM platforms
# (Asahi, ARM VMs, Raspberry Pi)
# Replaces disk-based swap with compressed RAM swap:
#   - Avoids flash/SD card wear on Pi
#   - No btrfs NOCOW workarounds needed
#   - Faster than eMMC/SD I/O
# Uses systemd-zram-generator for automatic setup on every boot

# Only for ARM systems (check env vars from installer, or detect directly)
if [[ -z "${OMARCHY_ARM:-}" ]] && [[ -z "${ASAHI_ALARM:-}" ]] && [[ "$(uname -m)" != "aarch64" ]]; then
  exit 0
fi

# Skip if already configured
if [[ -f /etc/systemd/zram-generator.conf ]]; then
  echo "zram swap already configured, skipping"
  exit 0
fi

echo "Configuring zram compressed swap..."

# Migrate from disk-based swap if present (e.g. Pi upgrading from swap-pi500.sh)
if swapon --show | grep -q /swapfile; then
  sudo swapoff /swapfile 2>/dev/null || true
  echo "  - Disabled old disk-based swap"
fi
if [[ -f /swapfile ]]; then
  sudo rm -f /swapfile
  echo "  - Removed /swapfile"
fi
if grep -q "^/swapfile" /etc/fstab 2>/dev/null; then
  sudo sed -i '/^\/swapfile/d' /etc/fstab
  echo "  - Removed /swapfile from fstab"
fi
# Clean up old swappiness config (swap-pi500.sh used swappiness=10 for disk swap)
if [[ -f /etc/sysctl.d/99-swappiness.conf ]]; then
  sudo rm -f /etc/sysctl.d/99-swappiness.conf
  echo "  - Removed old disk-swap swappiness config"
fi

# Install zram-generator
if ! pacman -Q zram-generator &>/dev/null; then
  sudo pacman -S --needed --noconfirm zram-generator
  echo "  - Installed zram-generator"
fi

# Write zram-generator config (50% of RAM, zstd compression)
sudo tee /etc/systemd/zram-generator.conf >/dev/null <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF
echo "  - Created /etc/systemd/zram-generator.conf"

# Set swappiness to 180 (kernel-recommended for zram)
echo 'vm.swappiness=180' | sudo tee /etc/sysctl.d/99-zram-swappiness.conf >/dev/null
echo "  - Set vm.swappiness=180"

# Enable immediately
sudo systemctl daemon-reload
sudo systemctl start systemd-zram-setup@zram0.service 2>/dev/null || true
sudo sysctl vm.swappiness=180 >/dev/null
echo "  - Enabled zram swap"
