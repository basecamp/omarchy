if [[ -n ${OMARCHY_ONLINE_INSTALL:-} ]]; then
  # Configure pacman - use ARM-specific configs on ARM systems
  if [ -n "$OMARCHY_ARM" ]; then
    sudo cp -f ~/.local/share/omarchy/default/pacman/pacman.conf.arm /etc/pacman.conf
    sudo cp -f ~/.local/share/omarchy/default/pacman/mirrorlist.arm /etc/pacman.d/mirrorlist
    sudo cp -f ~/.local/share/omarchy/default/pacman/mirrorlist.asahi-alarm /etc/pacman.d/mirrorlist.asahi-alarm
  else
    sudo cp -f ~/.local/share/omarchy/default/pacman/pacman.conf /etc/pacman.conf
    sudo cp -f ~/.local/share/omarchy/default/pacman/mirrorlist /etc/pacman.d/mirrorlist
  fi

  # Refresh all repos with retry logic
  echo "Syncing package databases..."
  max_attempts=3
  attempt=1
  sync_success=false

  # TESTING: Simulate mirror being down
  if [[ -n "${OMARCHY_SIMULATE_MIRROR_DOWN:-}" ]]; then
    echo "MIRROR DOWN SIMULATION ENABLED - Forcing database sync to fail"
    sync_success=false
  else
    while [ $attempt -le $max_attempts ]; do
      echo "Database sync attempt $attempt/$max_attempts..."

      if sudo pacman -Sy --noconfirm 2>&1 | tee /tmp/pacman-sync.log; then
        # Check if sync actually succeeded (not just returned 0)
        if ! grep -q "failed to synchronize\|failed retrieving file\|Unrecognized archive format" /tmp/pacman-sync.log; then
          echo "Database sync successful"
          sync_success=true
          break
        fi
      fi

      # Sync failed, clean up corrupted databases
      echo "Database sync failed, cleaning corrupted databases..."
      sudo rm -f /var/lib/pacman/sync/*.db /var/lib/pacman/sync/*.db.sig

      if [ $attempt -lt $max_attempts ]; then
        echo "Waiting 5 seconds before retry..."
        sleep 5
      fi

      ((attempt++))
    done
  fi

  if [ "$sync_success" = false ]; then
    echo "ERROR: Failed to sync package databases after $max_attempts attempts"
    echo "This may be due to slow/unreachable mirrors. Check network connection."
    exit 1
  fi

  # Install build tools (using 'yes 1' to auto-select provider option 1)
  echo "Installing build tools..."
  yes 1 | sudo pacman -S --needed --noconfirm base-devel

  # Now do full system upgrade (using 'yes 1' to auto-select provider option 1)
  echo "Upgrading system packages..."
  yes 1 | sudo pacman -Su --noconfirm
fi
