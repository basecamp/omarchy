echo "Install libva-intel-driver alongside intel-media-driver for Intel GPU video acceleration"

# install/hardware/intel/video-acceleration.sh used to pick a single VA-API
# driver by matching the GPU's marketing name from lspci. "HD Graphics" names
# both Gen7 (Ivy Bridge, needs libva-intel-driver/i965) and Gen8+ (Broadwell+,
# needs intel-media-driver/iHD) parts, and some older generations (Ironlake,
# Sandy Bridge, Haswell-ULT) matched neither branch and got no driver at all.
# Existing installs on the wrong side of that regex are left with a driver
# that fails to initialize (or none), and this repair doesn't run itself, so
# bring them in line with the new install-time behavior: install both
# drivers and let libva pick the one that actually works for the GPU present.
if lspci | grep -iE 'vga|3d|display' | grep -qi 'intel'; then
  omarchy-pkg-add intel-media-driver libva-intel-driver libvpl vpl-gpu-rt
fi
