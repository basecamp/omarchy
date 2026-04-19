echo "Refresh resume boost and restart intel-lpmd for packaged defaults"

source "$OMARCHY_PATH/install/config/hardware/intel/resume-boost.sh"

if pacman -Q intel-lpmd &>/dev/null && omarchy-hw-intel && omarchy-battery-present; then
  sudo systemctl restart intel_lpmd.service || sudo systemctl start intel_lpmd.service
fi
