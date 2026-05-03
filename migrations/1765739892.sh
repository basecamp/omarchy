if omarchy-cmd-present btrfs && omarchy-cmd-present snapper; then
  echo "Adjust snapper space limits & enable btrfs quota"

  sudo sed -i 's/^SPACE_LIMIT="0.5"/SPACE_LIMIT="0.3"/' /etc/snapper/configs/{root,home} 2>/dev/null
  sudo sed -i 's/^FREE_LIMIT="0.2"/FREE_LIMIT="0.3"/' /etc/snapper/configs/{root,home} 2>/dev/null
  sudo btrfs quota enable /
fi
