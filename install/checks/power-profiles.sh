OMARCHY_DESCRIPTION="Power Profile & Battery Settings"

omarchy_verify() {
  if ls /sys/class/power_supply/BAT* &>/dev/null; then
    current_profile=$(powerprofilesctl get 2>/dev/null)
    [[ "$current_profile" == "balanced" ]] || add_error "Power profile not set to balanced for battery device"

    systemctl --user is-enabled omarchy-battery-monitor.timer &>/dev/null || add_error "Battery monitor timer not enabled"
  else
    current_profile=$(powerprofilesctl get 2>/dev/null)
    [[ "$current_profile" == "performance" ]] || add_error "Power profile not set to performance for AC device"
  fi
}
