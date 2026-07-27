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
# libinput scans /usr/share/libinput for *.quirks and additionally reads the
# single file /etc/libinput/local-overrides.quirks. It never scans /etc, so a
# drop-in is the only way to ship a quirk without editing the one override
# file users hand-edit themselves.
#
# The pad's event node is tagged ID_INPUT_MOUSE rather than ID_INPUT_TOUCHPAD,
# so a MatchUdevType=touchpad constraint would skip the section. Bus, vendor,
# product and DMI already pin the device exactly.

if omarchy-hw-asus-expertbook-b9406; then
  mkdir -p /usr/share/libinput
  cat > /usr/share/libinput/99-omarchy-asus-b9406-touchpad.quirks <<'EOF'
[ASUS ExpertBook B9406 Touchpad]
MatchBus=i2c
MatchVendor=0x093A
MatchProduct=0x4F05
MatchDMIModalias=dmi:*svnASUS*:pn*B9406*
AttrEventCode=-ABS_MT_PRESSURE;-ABS_PRESSURE;
EOF
fi
