echo "Disable btrfs quotas on existing installs"

if omarchy-cmd-present btrfs; then
  if sudo btrfs quota status / 2>/dev/null | grep -q "enabled"; then
    sudo btrfs quota disable /
  fi
fi
