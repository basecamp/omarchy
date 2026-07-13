# Install Sound Open Firmware for the audio DSP on Intel systems that need it.
# The sof-audio-pci-intel-* driver family requires sof-firmware to initialise
# the DSP; without it the DSP fails to boot and PipeWire exposes only a Dummy
# Output sink. This affects Arrow Lake, Meteor Lake, Tiger Lake, Alder Lake,
# Wildcat Lake, Panther Lake, and similar platforms.
#
# Mark the package explicit so the orphan sweep cannot remove firmware that was
# originally installed as a linux-ptl dependency.

if omarchy-hw-intel-sof; then
  omarchy-pkg-add sof-firmware
  sudo pacman -D --asexplicit sof-firmware >/dev/null
fi
