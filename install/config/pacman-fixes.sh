#!/bin/bash
# Refresh keyring and ensure pacman DB is in a good state, then clear any stale firmware cache.
# This version updates mirrors with reflector and retries installing linux-firmware to avoid checksum failures.
set -euo pipefail

echo "Refreshing pacman DB and keyring"
sudo pacman -Syy --noconfirm archlinux-keyring
sudo pacman-key --init || true
sudo pacman-key --populate archlinux || true

echo "Install reflector (best-effort) and update mirrorlist"
sudo pacman -S --noconfirm --needed reflector || true
sudo reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist || true

echo "Refresh DB after mirror update"
sudo pacman -Syy --noconfirm || true

echo "Remove possibly corrupted linux-firmware cache"
sudo rm -f /var/cache/pacman/pkg/linux-firmware-*.pkg.* || true

# Try installing linux-firmware with retries. On failure clear cache and retry.
attempts=3
for i in $(seq 1 $attempts); do
  echo "Attempt $i to install linux-firmware"
  if sudo pacman -S --noconfirm --needed linux-firmware; then
    echo "linux-firmware installed successfully"
    exit 0
  fi

  echo "Install failed (possible checksum/mirror issue). Clearing cache and retrying..."
  sudo rm -f /var/cache/pacman/pkg/linux-firmware-*.pkg.* || true
  sudo pacman -Scc --noconfirm || true
  sleep 2
done

echo "All attempts to install linux-firmware failed. Showing last pacman log lines for debugging:"
sudo tail -n 200 /var/log/pacman.log || true
exit 1
```// filepath: /home/himangshu/himangshu/projects/omarchy/install/config/pacman-fixes.sh
#!/bin/bash
# Refresh keyring and ensure pacman DB is in a good state, then clear any stale firmware cache.
# This version updates mirrors with reflector and retries installing linux-firmware to avoid checksum failures.
set -euo pipefail

echo "Refreshing pacman DB and keyring"
sudo pacman -Syy --noconfirm archlinux-keyring
sudo pacman-key --init || true
sudo pacman-key --populate archlinux || true

echo "Install reflector (best-effort) and update mirrorlist"
sudo pacman -S --noconfirm --needed reflector || true
sudo reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist || true

echo "Refresh DB after mirror update"
sudo pacman -Syy --noconfirm || true

echo "Remove possibly corrupted linux-firmware cache"
sudo rm -f /var/cache/pacman/pkg/linux-firmware-*.pkg.* || true

# Try installing linux-firmware with retries. On failure clear cache and retry.
attempts=3
for i in $(seq 1 $attempts); do
  echo "Attempt $i to install linux-firmware"
  if sudo pacman -S --noconfirm --needed linux-firmware; then
    echo "linux-firmware installed successfully"
    exit 0
  fi

  echo "Install failed (possible checksum/mirror issue). Clearing cache and retrying..."
  sudo rm -f /var/cache/pacman/pkg/linux-firmware-*.pkg.* || true
  sudo pacman -Scc --noconfirm || true
  sleep 2
done

echo "All attempts to install linux-firmware failed. Showing last pacman log lines for debugging:"
sudo tail -n 200 /var/log/pacman.log || true
exit 1