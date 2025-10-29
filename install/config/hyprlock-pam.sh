# Setup PAM configuration for Hyprlock screen locker
sudo mkdir -p /etc/pam.d
sudo cp ~/.local/share/omarchy/default/pam.d/hyprlock /etc/pam.d/
sudo chmod 644 /etc/pam.d/hyprlock
