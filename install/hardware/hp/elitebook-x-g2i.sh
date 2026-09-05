# HP EliteBook X G2i (Panther Lake) — speakers, mic and webcam
#
# This board ships hardware that no stock Linux path drives yet:
#
#   Audio  Quad TAS2783 smart amps + RT712 SDCA. Panther Lake's ACPI match table
#          has no entry for this pairing, so the machine falls back to a
#          barebones machine driver and NO Speaker device appears at all -- not
#          quiet, absent. The match-table entry and a component name for the
#          TAS2783A ship as patches in linux-ptl, installed just above by
#          intel/ptl-kernel.sh. This package is the userspace remainder: the
#          Speaker device definition, the firmware filename links the tas2783
#          driver asks for, and two layers of protection against the amp
#          enumeration race at boot.
#
#   Webcam OmniVision OV05C10 on IPU7. Intel's CamHAL does not produce usable
#          frames here -- psys completes them and the output is black -- and the
#          cause is not established. The package bypasses psys/CamHAL and does
#          debayer, auto exposure and white balance in userspace instead. See its
#          README for the trade-offs and for why the obvious reading of the crop
#          log is wrong. It is a workaround, and the hardware path remains an
#          open question rather than a closed one.
#
# Both are gated on the model string so they cannot touch other EliteBooks,
# whose speaker layout and camera module differ.

if omarchy-hw-match "EliteBook X G2i"; then
  omarchy-pkg-add hp-elitebook-x-g2i-audio

  # The camera stack only makes sense where the IPU7 + OV05C10 pairing is
  # actually fitted; the audio fix applies to the whole model line. This DSDT
  # declares three sensors it does not have, so match on ACPI _STA rather than
  # on the HID appearing at all.
  if omarchy-hw-acpi-present OVTI05C1; then
    # Machines set up before ipu7-camera.sh checked _STA got intel-ipu7-camera
    # for a declared-but-absent sensor. The two packages conflict, and pacman
    # --noconfirm answers a conflict prompt with no, so the add below would
    # fail on every rerun until the wrong package is retired.
    omarchy-pkg-drop intel-ipu7-camera
    omarchy-pkg-add hp-elitebook-x-g2i-camera
  fi
fi
