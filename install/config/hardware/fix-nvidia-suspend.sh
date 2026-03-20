# Fix Hyprland freeze on suspend/resume with NVIDIA GPUs
# nvidia-utils disables session freezing during suspend, which causes Wayland
# clients to keep running while the GPU suspends. This creates a race condition
# that crashes hyprlock (SIGSEGV) and freezes the compositor.
# Solution: Pause Hyprland with SIGSTOP before NVIDIA suspends, resume with SIGCONT after.
# See: https://github.com/basecamp/omarchy/issues/4891
# See: https://github.com/0xFMD/hyprland-suspend-fix

NVIDIA="$(lspci | grep -i 'nvidia')"

if [ -n "$NVIDIA" ]; then
  echo "Installing NVIDIA suspend fix for Hyprland..."

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
  chrootable_systemctl_enable omarchy-hyprland-suspend.service
  chrootable_systemctl_enable omarchy-hyprland-resume.service
fi
