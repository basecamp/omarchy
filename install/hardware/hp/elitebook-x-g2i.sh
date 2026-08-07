# HP EliteBook X G2i (Panther Lake) — speakers, mic and webcam
#
# This board ships hardware that no stock Linux path drives yet:
#
#   Audio  Quad TAS2783 smart amps + RT712 SDCA. Panther Lake's ACPI match table
#          has no entry for this pairing, so the machine falls back to a
#          barebones machine driver and NO Speaker device appears at all -- not
#          quiet, absent. The package adds the match-table entry via DKMS (so it
#          survives kernel upgrades), a UCM profile, and the firmware filename
#          links the tas2783 driver asks for but linux-firmware does not ship.
#
#   Webcam OmniVision OV05C10 on IPU7. Intel's CamHAL cannot drive it: its graph
#          settings binary is built for a 2944-wide readout while the sensor
#          exposes 2888x1808, so the ISP receives a negative crop and emits
#          black frames. The package bypasses psys/CamHAL and does debayer, auto
#          exposure and white balance in userspace instead. See its README for
#          the trade-offs -- it is a workaround, not a fix, and the underlying
#          bug is filed against intel/ipu7-camera-hal.
#
# Both are gated on the model string so they cannot touch other EliteBooks,
# whose speaker layout and camera module differ.

if omarchy-hw-match "EliteBook X G2i"; then
  omarchy-pkg-add hp-elitebook-x-g2i-audio

  # The camera stack only makes sense where the IPU7 + OV05C10 pairing is
  # actually present; the audio fix applies to the whole model line.
  if grep -q "OVTI05C1" /sys/bus/acpi/devices/*/hid 2>/dev/null; then
    omarchy-pkg-add hp-elitebook-x-g2i-camera
  fi
fi
