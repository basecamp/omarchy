# This installs hardware video acceleration for Intel GPUs

# Select on the presence of an Intel display device rather than on the marketing
# name lspci reports. Intel ships recent parts -- Raptor Lake, Meteor Lake,
# Arrow Lake, Lunar Lake, Battlemage -- as a bare "[Intel Graphics]" with no
# Iris, UHD or Arc branding, so an allowlist of names installs nothing at all on
# them and has to be widened for every new family; "panther lake" was added for
# exactly that reason. Inverting the test leaves only the pre-Broadwell parts
# needing a name, and that set stopped growing in 2014.
if INTEL_GPU=$(lspci -d '8086::0300') && [[ -n $INTEL_GPU ]]; then
  if [[ ${INTEL_GPU,,} =~ gma ]]; then
    # Older generations from 2008 to ~2014-2017 use libva-intel-driver
    omarchy-pkg-add libva-intel-driver
  else
    # Broadwell and newer use intel-media-driver + VPL
    omarchy-pkg-add intel-media-driver libvpl vpl-gpu-rt
  fi
fi
