if omarchy-battery-present; then
  omarchy-powerprofiles-set battery || true

  # Enable battery monitoring timer for low battery notifications
  systemctl --user enable --now omarchy-battery-monitor.timer
else
  omarchy-powerprofiles-set ac || true
fi
