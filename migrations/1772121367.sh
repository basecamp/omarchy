echo "Install limine bootloader theme color support"

if [[ -f /boot/limine.conf ]]; then
  sudo cp "$OMARCHY_PATH/bin/omarchy-limine-update-colors" /usr/local/bin/omarchy-limine-update-colors
  sudo chmod 755 /usr/local/bin/omarchy-limine-update-colors
  sudo chown root:root /usr/local/bin/omarchy-limine-update-colors

  echo "%wheel ALL=(root) NOPASSWD: /usr/local/bin/omarchy-limine-update-colors" | sudo tee /etc/sudoers.d/omarchy-limine >/dev/null
  sudo chmod 440 /etc/sudoers.d/omarchy-limine
fi
