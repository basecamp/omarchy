# Set first-run mode marker so we can install stuff post-installation
mkdir -p ~/.local/state/omarchy
touch ~/.local/state/omarchy/first-run.mode

# Setup sudo-less access for first-run
sudo tee /etc/sudoers.d/first-run >/dev/null <<EOF
Cmnd_Alias FIRST_RUN_CLEANUP = /bin/rm -f /etc/sudoers.d/first-run
Cmnd_Alias INSTALLER_REBOOT_CLEANUP = /bin/rm -f /etc/sudoers.d/99-omarchy-installer-reboot
Cmnd_Alias SYMLINK_RESOLVED = /usr/bin/ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
Cmnd_Alias UFW_SERVICE_ENABLE = /usr/bin/systemctl enable ufw
$USER ALL=(ALL) NOPASSWD: UFW_SERVICE_ENABLE
$USER ALL=(ALL) NOPASSWD: /usr/bin/ufw
$USER ALL=(ALL) NOPASSWD: /usr/bin/ufw-docker
$USER ALL=(ALL) NOPASSWD: /usr/bin/gtk-update-icon-cache
$USER ALL=(ALL) NOPASSWD: SYMLINK_RESOLVED
$USER ALL=(ALL) NOPASSWD: FIRST_RUN_CLEANUP
$USER ALL=(ALL) NOPASSWD: INSTALLER_REBOOT_CLEANUP
EOF
sudo chmod 440 /etc/sudoers.d/first-run
