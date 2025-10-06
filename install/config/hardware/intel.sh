OMARCHY_DESCRIPTION="Setup Intel video acceleration"

should_run() {
  INTEL_GPU=$(lspci | grep -iE 'vga|3d|display' | grep -i 'intel' || true)
  [[ -n "$INTEL_GPU" ]]
}

omarchy_install() {
  should_run || return 0

  # HD Graphics and newer uses intel-media-driver
  if [[ "${INTEL_GPU,,}" =~ "hd graphics"|"xe"|"iris" ]]; then
      sudo pacman -S --needed --noconfirm intel-media-driver
  elif [[ "${INTEL_GPU,,}" =~ "gma" ]]; then
      # Older generations from 2008 to ~2014-2017 use libva-intel-driver
      sudo pacman -S --needed --noconfirm libva-intel-driver
  fi
}

# Verification function
omarchy_verify() {
  should_run || return 2

  # Check if appropriate driver is installed
  if [[ "${INTEL_GPU,,}" =~ "hd graphics"|"xe"|"iris" ]]; then
      pacman -Q intel-media-driver &>/dev/null || add_error "Intel media driver not installed"
  elif [[ "${INTEL_GPU,,}" =~ "gma" ]]; then
      pacman -Q libva-intel-driver &>/dev/null || add_error "Intel VA-API driver not installed"
  fi
}
