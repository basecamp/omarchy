# Install Sound Open Firmware for the audio DSP on Intel Panther Lake and
# Wildcat Lake systems (the latter includes the XPS13 2026). Mainline
# `linux` only optdeps sof-firmware, so without it the DSP fails to boot
# and only auto_null shows up in PipeWire. Idempotent on XPS PTL machines
# that already pull it in via linux-ptl.

if omarchy-hw-intel-ptl || omarchy-hw-intel-wcl; then
  omarchy-pkg-add sof-firmware
fi
