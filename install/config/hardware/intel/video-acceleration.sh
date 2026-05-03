# This installs hardware video acceleration for Intel GPUs

if INTEL_GPU=$(lspci | grep -iE 'vga|3d|display' | grep -i 'intel'); then
  # HD Graphics / Iris / Xe / Arc use intel-media-driver + VPL
  if [[ ${INTEL_GPU,,} =~ (hd\ graphics|uhd\ graphics|xe|iris|arc) ]]; then
    omarchy-pkg-add intel-media-driver libvpl vpl-gpu-rt
  elif [[ ${INTEL_GPU,,} =~ "gma" ]]; then
    # Older generations from 2008 to ~2014-2017 use libva-intel-driver
    omarchy-pkg-add libva-intel-driver
  fi
fi
