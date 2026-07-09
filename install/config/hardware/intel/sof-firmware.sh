# Install Sound Open Firmware for the audio DSP on Intel systems that need it.
# The sof-audio-pci-intel-* driver family requires sof-firmware to initialise
# the DSP; without it the DSP fails to boot and PipeWire exposes only a
# Dummy Output sink. This affects Arrow Lake, Meteor Lake, Tiger Lake,
# Alder Lake, and similar platforms — not just Panther Lake.
#
# Panther Lake XPS systems are excluded because their linux-ptl kernel
# already hard-depends sof-firmware, so the package is always present.
# All other Intel SOF platforms on mainline linux need it installed explicitly.

if omarchy-hw-intel-sof && ! (omarchy-hw-intel-ptl && omarchy-hw-match "XPS"); then
  omarchy-pkg-add sof-firmware
fi
