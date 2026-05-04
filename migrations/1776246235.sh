echo "Fix empty resume_offset in hibernation config"

RESUME_DROP_IN="/etc/limine-entry-tool.d/resume.conf"
SWAP_FILE="/swap/swapfile"

if [[ -f $RESUME_DROP_IN ]] && grep -q 'resume_offset="$' "$RESUME_DROP_IN" && [[ -f $SWAP_FILE ]]; then
  RESUME_OFFSET=$(sudo btrfs inspect-internal map-swapfile -r "$SWAP_FILE" 2>/dev/null)
  if [[ -n $RESUME_OFFSET ]]; then
    sudo sed -i "s/resume_offset=\"$/resume_offset=$RESUME_OFFSET\"/" "$RESUME_DROP_IN"
    sudo sed -i "s/resume_offset=\"$/resume_offset=$RESUME_OFFSET\"/" /etc/default/limine
    sudo limine-mkinitcpio
    sudo limine-update
    echo "Fixed: resume_offset=$RESUME_OFFSET"
  else
    echo "Warning: Could not determine resume offset for $SWAP_FILE"
  fi
fi
