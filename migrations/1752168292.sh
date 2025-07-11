echo "Enable battery low notifications for laptops"

if ls /sys/class/power_supply/BAT* &>/dev/null; then
  mkdir -p ~/.config/systemd/user

  cp ~/.local/share/omarchy/config/systemd/user/omarchy-battery-monitor.* ~/.config/systemd/user/

  systemctl --user daemon-reload
  systemctl --user enable --now omarchy-battery-monitor.timer || true

  echo "Battery monitoring enabled - you'll receive notifications at 10% battery"
else
  echo "No battery detected - skipping battery monitor setup"
fi
