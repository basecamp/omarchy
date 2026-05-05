echo "Enable monthly btrfs scrub on root (uses btrfs-progs's btrfs-scrub@.timer)"

if [[ $(findmnt -no FSTYPE / 2>/dev/null) != "btrfs" ]]; then
  exit 0
fi

sudo systemctl enable --now btrfs-scrub@-.timer
