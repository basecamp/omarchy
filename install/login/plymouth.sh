if [[ $(plymouth-set-default-theme) != "omarchy" ]]; then
  sudo cp -r "$HOME/.local/share/omarchy/default/plymouth" /usr/share/plymouth/themes/omarchy/
  sudo plymouth-set-default-theme omarchy
fi

# Install plymouth theme color helper for passwordless theme updates
sudo cp "$OMARCHY_PATH/bin/omarchy-plymouth-update-theme" /usr/local/bin/omarchy-plymouth-update-theme
sudo chmod 755 /usr/local/bin/omarchy-plymouth-update-theme
sudo chown root:root /usr/local/bin/omarchy-plymouth-update-theme

echo "%wheel ALL=(root) NOPASSWD: /usr/local/bin/omarchy-plymouth-update-theme *" | sudo tee /etc/sudoers.d/omarchy-plymouth >/dev/null
sudo chmod 440 /etc/sudoers.d/omarchy-plymouth
