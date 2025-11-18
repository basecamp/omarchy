# Set balanced profile to allow power savings when idle
powerprofilesctl set balanced || true

if ls /sys/class/power_supply/BAT* &>/dev/null; then
  # This computer runs on a battery
  # Enable battery monitoring timer for low battery notifications
  systemctl --user enable --now omarchy-battery-monitor.timer
fi
