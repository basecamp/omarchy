# Enable monthly btrfs scrub on the root filesystem so silent bitrot is
# detected (and corrected via the second copy / parity if redundancy exists).
# btrfs-progs ships the btrfs-scrub@.timer template — we just enable the
# instance for "/". The instance name "-" is systemd-escape for "/".
#
# No-op if root isn't btrfs (e.g. someone is using ext4).

if [[ $(findmnt -no FSTYPE / 2>/dev/null) != "btrfs" ]]; then
  exit 0
fi

chrootable_systemctl_enable btrfs-scrub@-.timer
