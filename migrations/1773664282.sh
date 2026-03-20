echo "Install NVIDIA suspend fix for Hyprland (prevents freeze on resume)"

NVIDIA="$(lspci | grep -i 'nvidia')"

if [ -z "$NVIDIA" ]; then
  exit 0
fi

# Skip if already installed
if systemctl is-enabled omarchy-hyprland-suspend.service &>/dev/null; then
  exit 0
fi

cat <<EOF | sudo tee /etc/systemd/system/omarchy-hyprland-suspend.service >/dev/null
[Unit]
Description=Pause Hyprland before NVIDIA GPU suspend
Before=systemd-suspend.service
Before=systemd-hibernate.service
Before=nvidia-suspend.service
Before=nvidia-hibernate.service

[Service]
Type=oneshot
ExecStart=/usr/bin/killall -STOP Hyprland

[Install]
WantedBy=systemd-suspend.service
WantedBy=systemd-hibernate.service
EOF

cat <<EOF | sudo tee /etc/systemd/system/omarchy-hyprland-resume.service >/dev/null
[Unit]
Description=Resume Hyprland after NVIDIA GPU resume
After=systemd-suspend.service
After=systemd-hibernate.service
After=nvidia-resume.service

[Service]
Type=oneshot
ExecStart=/usr/bin/killall -CONT Hyprland

[Install]
WantedBy=systemd-suspend.service
WantedBy=systemd-hibernate.service
EOF

sudo systemctl daemon-reload
sudo systemctl enable omarchy-hyprland-suspend.service
sudo systemctl enable omarchy-hyprland-resume.service
