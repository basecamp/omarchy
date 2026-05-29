echo "Install t2-suspend T2 suspend/resume service"

if lspci -nn 2>/dev/null | grep -q "106b:180[12]"; then
  sudo mkdir -p /usr/local/libexec/omarchy/apple
  sudo cp "$OMARCHY_PATH/install/config/hardware/apple/t2-suspend" /usr/local/libexec/omarchy/apple/t2-suspend
  sudo chmod +x /usr/local/libexec/omarchy/apple/t2-suspend

  sudo tee /etc/systemd/system/omarchy-apple-t2-suspend.service >/dev/null <<'UNIT_EOF'
[Unit]
Description=Apple T2 suspend/resume
Before=sleep.target
StopWhenUnneeded=yes

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/libexec/omarchy/apple/t2-suspend pre
ExecStop=/usr/local/libexec/omarchy/apple/t2-suspend post
TimeoutStopSec=10

[Install]
WantedBy=sleep.target
UNIT_EOF

  sudo systemctl daemon-reload
  sudo systemctl enable omarchy-apple-t2-suspend.service
  echo "T2 suspend/resume service installed and enabled."
fi
