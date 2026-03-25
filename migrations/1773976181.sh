echo "Disable btrfs quotas and space-aware snapper limits on existing installs"

if omarchy-cmd-present btrfs; then
  if sudo btrfs quota status / 2>/dev/null | grep -q "Quota enabled: yes"; then
    sudo btrfs quota disable /
  fi
fi

if omarchy-cmd-present snapper; then
  sudo sed -i 's/^SPACE_LIMIT="0\.3"/SPACE_LIMIT="0"/' /etc/snapper/configs/{root,home} 2>/dev/null
  sudo sed -i 's/^FREE_LIMIT="0\.3"/FREE_LIMIT="0"/' /etc/snapper/configs/{root,home} 2>/dev/null
fi
