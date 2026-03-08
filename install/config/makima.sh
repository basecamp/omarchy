# Remap Copilot key (Super+Shift+F23) to Super+Alt+Space (Omarchy Menu) using makima
mkdir -p "$HOME/.config/makima"
cp "$OMARCHY_PATH/default/makima/AT Translated Set 2 keyboard.toml" "$HOME/.config/makima/"

# Create systemd override with correct user and config path
sudo mkdir -p /etc/systemd/system/makima.service.d
sudo tee /etc/systemd/system/makima.service.d/override.conf > /dev/null <<EOF
[Service]
User=$USER
Environment="MAKIMA_CONFIG=/home/$USER/.config/makima"
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now makima 2>/dev/null || true
