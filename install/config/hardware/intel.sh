# This installs hardware video acceleration for Intel GPUs
# Check if we have an Intel GPU at all
if INTEL_GPU=$(lspci | grep -iE 'vga|3d|display' | grep -i 'intel'); then
  # HD Graphics and newer uses intel-media-driver
  if [[ ${INTEL_GPU,,} =~ "hd graphics"|"xe"|"iris" ]]; then
    omarchy-pkg-add intel-media-driver
  elif [[ ${INTEL_GPU,,} =~ "gma" ]]; then
    # Older generations from 2008 to ~2014-2017 use libva-intel-driver
    omarchy-pkg-add libva-intel-driver
  fi
fi
