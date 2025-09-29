echo "Re-enabling mkinitcpio hooks..."

# Restore the specific mkinitcpio pacman hooks
if [ -f /usr/share/libalpm/hooks/90-mkinitcpio-install.hook.disabled ]; then
  sudo mv /usr/share/libalpm/hooks/90-mkinitcpio-install.hook.disabled /usr/share/libalpm/hooks/90-mkinitcpio-install.hook
fi

if [ -f /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook.disabled ]; then
  sudo mv /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook.disabled /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook
fi

echo "mkinitcpio hooks re-enabled"

if command -v limine &>/dev/null; then
  if [[ "$(uname -m)" == "aarch64" ]] || [[ "$(uname -m)" == "arm64" ]]; then
    sudo "$OMARCHY_PATH/bin/omarchy-limine-update"
  else
    sudo limine-update
  fi
else
  # Run mkinitcpio but don't fail on warnings (like missing fsck helpers)
  # The initramfs is still created, just without optional features
  sudo mkinitcpio -P || {
    exit_code=$?
    echo "mkinitcpio exited with code $exit_code - checking if initramfs was created..."
    if [ -f /boot/initramfs-linux.img ]; then
      echo "Initramfs created successfully despite warnings, continuing..."
    else
      echo "Failed to create initramfs, exiting..."
      exit $exit_code
    fi
  }
fi
