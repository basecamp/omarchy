echo "Fix hibernation on btrfs swapfiles with dm-crypt (systemd 256+)"

MKINITCPIO_CONF="/etc/mkinitcpio.conf.d/omarchy_resume.conf"
SWAP_FILE="/swap/swapfile"
RESUME_DROP_IN="/etc/limine-entry-tool.d/resume.conf"

# Only apply if hibernation is configured
if [[ ! -f $MKINITCPIO_CONF ]] || ! grep -q "^HOOKS+=(resume)$" "$MKINITCPIO_CONF"; then
  exit 0
fi

# Add systemd bypass drop-ins for btrfs swapfile on dm-crypt
# (see https://github.com/systemd/systemd/issues/30083)
LOGIND_DROP_IN="/etc/systemd/system/systemd-logind.service.d/hibernate.conf"
if [[ ! -f $LOGIND_DROP_IN ]]; then
  sudo mkdir -p /etc/systemd/system/systemd-logind.service.d
  printf '[Service]\nEnvironment="SYSTEMD_BYPASS_HIBERNATION_MEMORY_CHECK=1"\n' | sudo tee "$LOGIND_DROP_IN" >/dev/null
fi

HIBERNATE_DROP_IN="/etc/systemd/system/systemd-hibernate.service.d/bypass.conf"
if [[ ! -f $HIBERNATE_DROP_IN ]]; then
  sudo mkdir -p /etc/systemd/system/systemd-hibernate.service.d
  printf '[Service]\nEnvironment="SYSTEMD_BYPASS_HIBERNATION_MEMORY_CHECK=1"\n' | sudo tee "$HIBERNATE_DROP_IN" >/dev/null
fi

# Fix stale resume_offset if swapfile was recreated at a different physical location
if [[ -f $RESUME_DROP_IN ]] && [[ -f $SWAP_FILE ]]; then
  RESUME_OFFSET=$(sudo btrfs inspect-internal map-swapfile -r "$SWAP_FILE" 2>/dev/null)
  if [[ -n $RESUME_OFFSET ]] && ! grep -q "resume_offset=$RESUME_OFFSET" "$RESUME_DROP_IN"; then
    sudo sed -i "s/resume_offset=[0-9]*/resume_offset=$RESUME_OFFSET/" "$RESUME_DROP_IN"
    sudo sed -i "s/resume_offset=[0-9]*/resume_offset=$RESUME_OFFSET/" /etc/default/limine
    sudo limine-mkinitcpio
  fi
fi
