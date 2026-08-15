echo "Enable monthly btrfs scrub on root (uses btrfs-progs's btrfs-scrub@.timer)"

if [[ $(findmnt -no FSTYPE / 2>/dev/null) != "btrfs" ]]; then
  exit 0
fi

if ! systemctl list-unit-files 'btrfs-scrub@-.timer' --no-legend 2>/dev/null | grep -q '^btrfs-scrub@-.timer'; then
  echo "Skipping btrfs scrub timer: btrfs-scrub@-.timer is unavailable (btrfs-progs may not be installed)"
  exit 0
fi

sudo systemctl enable --now btrfs-scrub@-.timer
