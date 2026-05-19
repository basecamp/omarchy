echo "Move low battery notifications into omarchy-shell"

systemctl --user disable --now omarchy-battery-monitor.timer 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/omarchy-battery-monitor.service" "$HOME/.config/systemd/user/omarchy-battery-monitor.timer"
systemctl --user daemon-reload 2>/dev/null || true
