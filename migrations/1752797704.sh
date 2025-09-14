echo "Prevent docker from requiring network readiness on boot"

if [[ ! -f /etc/systemd/system/docker.service.d/no-block-boot.conf ]]; then
  sudo mkdir -p /etc/systemd/system/docker.service.d/
  sudo tee /etc/systemd/system/docker.service.d/no-block-boot.conf <<'EOF'
[Unit]
DefaultDependencies=no
EOF

  sudo mkdir -p /etc/systemd/system/plymouth-quit.service.d/
  sudo tee /etc/systemd/system/plymouth-quit.service.d/wait-for-graphical.conf <<'EOF'
[Unit]
After=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl mask plymouth-quit-wait.service
fi
