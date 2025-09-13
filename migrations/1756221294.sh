echo "Ensure DNS resolution is happening through systemd-resolved"

sudo systemctl enable --now systemd-resolved
