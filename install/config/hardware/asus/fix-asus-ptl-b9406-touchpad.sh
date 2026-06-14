# Touchpad quirks for ASUS ExpertBook B9406 (Pixart 093A:4F05 on i2c-hid).
#
# The kernel produces perfect Precision Touchpad reports but libinput's
# jump-detection heuristic discards every motion event as "kernel bug:
# Touch jump detected and discarded" because the pad reports pressure
# values of 0-1, confusing the contact stability check. Button events
# still pass, so clicks register but motion does not.
#
# Mask the pressure axes with a quirks override, same pattern as the
# Asus UX302LA entry in libinput's shipped 50-system-asus.quirks.
#
# Two things matter for the override to take effect:
#   1. libinput reads only ONE override file, /etc/libinput/local-overrides.quirks.
#      Custom-named files in /etc/libinput/ are never loaded.
#   2. udev tags this pad as ID_INPUT_MOUSE, not ID_INPUT_TOUCHPAD, so a
#      MatchUdevType=touchpad section is skipped. The bus/vendor/product/DMI
#      keys already pin the device exactly, so we omit the type constraint.

if omarchy-hw-asus-expertbook-b9406; then
  QUIRKS_FILE="/etc/libinput/local-overrides.quirks"
  QUIRKS_SECTION="[ASUS ExpertBook B9406 Touchpad]"

  # Remove the stale, never-read file written by earlier Omarchy versions.
  sudo rm -f /etc/libinput/asus-expertbook-b9406.quirks

  # Append our section to the shared override file, but only once.
  if ! sudo grep -qF "$QUIRKS_SECTION" "$QUIRKS_FILE" 2>/dev/null; then
    sudo mkdir -p /etc/libinput
    sudo tee -a "$QUIRKS_FILE" >/dev/null <<EOF

$QUIRKS_SECTION
MatchBus=i2c
MatchVendor=0x093A
MatchProduct=0x4F05
MatchDMIModalias=dmi:*svnASUS*:pn*B9406*
AttrEventCode=-ABS_MT_PRESSURE;-ABS_PRESSURE;
EOF
  fi
fi
