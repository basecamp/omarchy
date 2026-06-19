# Set up Btrfs snapshots with Snapper + GRUB integration on Fedora.
# Fedora uses GRUB2, not Limine. This script sets up Snapper for root snapshots
# and installs grub-btrfs so snapshots appear in the GRUB boot menu.
# If the root filesystem is not Btrfs, this step is skipped gracefully.

if [[ $(findmnt -n -o FSTYPE /) != "btrfs" ]]; then
  echo "Root filesystem is not Btrfs — skipping Snapper/GRUB snapshot setup"
  exit 0
fi

echo -e "\e[32m\nSetting up Btrfs snapshots with Snapper\e[0m"

# Install snapper and grub-btrfs for snapshot boot entries
omarchy-pkg-add snapper grub-btrfs

# Create root snapshot config if it doesn't already exist
if ! sudo snapper list-configs 2>/dev/null | grep -q "root"; then
  sudo snapper -c root create-config /
fi

# Copy Omarchy's snapper config (limits snapshot count, etc.)
if [[ -f "$OMARCHY_PATH/default/snapper/root" ]]; then
  sudo cp "$OMARCHY_PATH/default/snapper/root" /etc/snapper/configs/root
fi

# Disable btrfs quotas — full qgroup accounting is a major performance drag
sudo btrfs quota disable / 2>/dev/null || true

# Enable snapper timeline and cleanup services
sudo systemctl enable --now snapper-timeline.timer
sudo systemctl enable --now snapper-cleanup.timer

# Enable grub-btrfs to rebuild GRUB menu when snapshots change
sudo systemctl enable --now grub-btrfsd.service

echo "Snapper and grub-btrfs configured"
