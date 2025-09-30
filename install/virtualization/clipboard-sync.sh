#!/bin/bash

# Shared clipboard sync installation for VMware/Parallels
# Sets up bidirectional X11 ↔ Wayland clipboard synchronization

# Install clipboard dependencies
echo "Installing clipboard dependencies..."
sudo pacman -S --noconfirm --needed xclip clipnotify wl-clipboard wl-clip-persist

# Install clipboard sync scripts
echo "Installing clipboard sync scripts..."
sudo install -m 755 "$OMARCHY_PATH/bin/omarchy-clipboard-wl-to-x11" /usr/local/bin/omarchy-clipboard-wl-to-x11
sudo install -m 755 "$OMARCHY_PATH/bin/omarchy-clipboard-x11-to-wl" /usr/local/bin/omarchy-clipboard-x11-to-wl

# Create clipboard sync services
echo "Creating clipboard sync services..."
sudo tee /etc/systemd/user/omarchy-clipboard-wl-to-x11.service <<'EOF' >/dev/null
[Unit]
Description=Omarchy Wayland → X11 Clipboard Sync
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/local/bin/omarchy-clipboard-wl-to-x11
Restart=always
RestartSec=3

[Install]
WantedBy=graphical-session.target
EOF

sudo tee /etc/systemd/user/omarchy-clipboard-x11-to-wl.service <<'EOF' >/dev/null
[Unit]
Description=Omarchy X11 → Wayland Clipboard Sync
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/local/bin/omarchy-clipboard-x11-to-wl
Restart=always
RestartSec=3

[Install]
WantedBy=graphical-session.target
EOF

# Enable clipboard sync services
sudo systemctl --global enable omarchy-clipboard-wl-to-x11.service
sudo systemctl --global enable omarchy-clipboard-x11-to-wl.service

echo "Clipboard synchronization configured for Wayland ↔ X11"
