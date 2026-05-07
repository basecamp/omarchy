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

if omarchy-hw-asus-expertbook-b9406; then
  sudo mkdir -p /etc/libinput
  sudo tee /etc/libinput/asus-expertbook-b9406.quirks >/dev/null <<EOF
[ASUS ExpertBook B9406 Touchpad]
MatchBus=i2c
MatchUdevType=touchpad
MatchVendor=0x093A
MatchProduct=0x4F05
MatchDMIModalias=dmi:*svnASUS*:pn*B9406*
AttrEventCode=-ABS_MT_PRESSURE;-ABS_PRESSURE;
EOF
fi
