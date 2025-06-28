# Turn on bluetooth by default
sudo systemctl enable --now bluetooth.service

# Install bluetooth controls
yay -S --noconfirm --needed blueberry
