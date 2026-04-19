echo "Refresh intel-lpmd integration to use packaged profile defaults"

if pacman -Q intel-lpmd &>/dev/null; then
  sudo systemctl enable intel_lpmd.service

  if omarchy-hw-intel && omarchy-battery-present; then
    sudo systemctl restart intel_lpmd.service || sudo systemctl start intel_lpmd.service
  fi
fi

source "$OMARCHY_PATH/install/config/hardware/intel/resume-boost.sh"
sudo rm -f /etc/sudoers.d/omarchy-intel-lpmd
