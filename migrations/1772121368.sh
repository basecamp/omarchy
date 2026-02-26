echo "Install plymouth theme color support"

sudo cp "$OMARCHY_PATH/bin/omarchy-plymouth-update-theme" /usr/local/bin/omarchy-plymouth-update-theme
sudo chmod 755 /usr/local/bin/omarchy-plymouth-update-theme
sudo chown root:root /usr/local/bin/omarchy-plymouth-update-theme

echo "%wheel ALL=(root) NOPASSWD: /usr/local/bin/omarchy-plymouth-update-theme *" | sudo tee /etc/sudoers.d/omarchy-plymouth >/dev/null
sudo chmod 440 /etc/sudoers.d/omarchy-plymouth
