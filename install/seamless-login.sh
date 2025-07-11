#!/bin/bash
# Seamless auto-login without SDDM dependency
# Replicates SDDM's VT management approach

echo "Setting up seamless auto-login..."

# Install UWSM for systemd integration
echo "Installing UWSM..."
yay -S --noconfirm --needed uwsm

# Compile the seamless login helper
echo "Compiling seamless login helper..."
gcc -o /tmp/seamless-login "$HOME/.local/share/omarchy/install/seamless-login.c"
sudo mv /tmp/seamless-login /usr/local/bin/seamless-login
sudo chmod +x /usr/local/bin/seamless-login

# Create the systemd service file directly (replicating SDDM's approach)
cat << EOF | sudo tee /etc/systemd/system/omarchy-seamless-login.service
[Unit]
Description=Omarchy Seamless Auto-Login
Documentation=https://github.com/basecamp/omarchy
Conflicts=getty@tty1.service
After=systemd-user-sessions.service getty@tty1.service plymouth-quit.service systemd-logind.service
PartOf=graphical.target

[Service]
Type=simple
ExecStart=/usr/local/bin/seamless-login uwsm start -- hyprland.desktop
User=$USER
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
StandardInput=tty
StandardOutput=journal
StandardError=journal+console
PAMName=login
Environment=XDG_SESSION_TYPE=wayland
Environment=XDG_VTNR=1
Environment=HOME=$HOME
WorkingDirectory=$HOME

[Install]
WantedBy=graphical.target
EOF

# Enable the service
sudo systemctl daemon-reload
sudo systemctl enable omarchy-seamless-login.service

# Disable getty@tty1 to prevent conflicts
sudo systemctl disable getty@tty1.service

echo ""
echo "Seamless auto-login configured!"
echo "This replicates SDDM's VT management for smooth Plymouth transition."
echo "Reboot to test the seamless transition."