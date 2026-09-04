# Mark the internal trackpad on T2 Macs as internal.
#
# The T2 bridge exposes the built-in keyboard and trackpad over a virtual USB
# host controller (t2bce_vhci), so the trackpad carries ID_BUS=usb and
# /usr/lib/udev/rules.d/65-integration.rules classifies it as external. libinput
# makes disable-while-typing unavailable on external touchpads, so a palm
# resting on the pad moves the cursor while typing.
#
# Nothing reports this as broken, which is what makes it hard to find. The
# compositor option is set and reads back as enabled, while libinput has no such
# setting to apply:
#
#   $ hyprctl getoption input:touchpad:disable_while_typing
#   int: 1
#   $ libinput list-devices | grep -A20 Trackpad | grep Disable-w-typing
#   Disable-w-typing:  n/a
#
# 70-touchpad.rules runs after 65-integration.rules precisely so hwdb entries can
# override the bus-based guess, so this is the supported correction rather than a
# workaround. Same class of bug as install/hardware/asus/fix-z13-touchpad.sh,
# where a detachable keyboard's touchpad is also detected as external.
#
# Matched on the USB ID the bridged keyboard/trackpad enumerates with, verified
# on a MacBookPro16,1. Other T2 models may report a different product ID; widen
# the match as they are reported rather than guessing at the range here.

if lspci -nn | grep "106b:180[12]" >/dev/null; then
  echo "Detected a T2 Mac; marking its internal trackpad as internal"

  mkdir -p /etc/udev/hwdb.d
  cat > /etc/udev/hwdb.d/70-omarchy-t2-touchpad.hwdb <<'EOF'
# Apple internal keyboard/trackpad, bridged over the T2's virtual USB HCI.
touchpad:usb:v05acp0340:*
 ID_INPUT_TOUCHPAD_INTEGRATION=internal
EOF

  # Compiles the text entry into the binary database udev actually reads.
  systemd-hwdb update
fi
