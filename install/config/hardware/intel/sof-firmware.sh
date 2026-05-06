# Install Sound Open Firmware for the audio DSP on non-XPS Intel Panther
# Lake systems. XPS PTL stays on linux-ptl, which hard-deps sof-firmware.
# Mainline `linux` only optdeps it, so without this the DSP fails to boot
# and only auto_null shows up in PipeWire.

if omarchy-hw-intel-ptl && ! omarchy-hw-match "XPS"; then
  omarchy-pkg-add sof-firmware
fi
