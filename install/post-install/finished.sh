# Installation completed in chroot
echo "[finished] Chroot installation completed successfully"

# Clean up installer sudoers
if sudo test -f /etc/sudoers.d/99-omarchy-installer; then
  sudo rm -f /etc/sudoers.d/99-omarchy-installer &>/dev/null
fi
