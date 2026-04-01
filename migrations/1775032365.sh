echo "Install Once for managing self-hosted web applications"

omarchy-pkg-add once-bin
sudo systemctl enable --now once-background.service
