# Allow passwordless operations for the installer - removed in first-run
sudo tee /etc/sudoers.d/99-omarchy-installer-reboot >/dev/null <<EOF
$USER ALL=(ALL) NOPASSWD: /usr/bin/reboot
$USER ALL=(ALL) NOPASSWD: /bin/cp
$USER ALL=(ALL) NOPASSWD: /bin/chmod
$USER ALL=(ALL) NOPASSWD: /usr/bin/test
$USER ALL=(ALL) NOPASSWD: /bin/rm
EOF
sudo chmod 440 /etc/sudoers.d/99-omarchy-installer-reboot
