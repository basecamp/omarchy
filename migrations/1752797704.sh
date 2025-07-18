echo "Prevent docker from requiring network readiness on boot"
sudo tee /etc/systemd/system/docker.service.d/no-block-boot.conf <<'EOF'
[Unit]
DefaultDependencies=no
EOF

sudo tee /etc/systemd/system/plymouth-quit.service.d/wait-for-graphical.conf <<'EOF'
[Unit]
After=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl unmask plymouth-quit-wait.service
