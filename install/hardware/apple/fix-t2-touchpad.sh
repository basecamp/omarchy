# Fix disable-while-typing on T2 Mac built-in trackpads.
#
# t2bce_vhci presents the keyboard/trackpad as USB with
# ATTR{removable}=="unknown", so udev marks the pad external. libinput
# then leaves disable-while-typing off. Thumbs resting on the clickpad
# jump the cursor while typing; Hyprland follow_mouse steals focus.
#
# Upstream libinput (50-system-apple.quirks) already marks the keyboard
# internal. Touchpad integration is a udev property, not a libinput
# quirk — same pattern as fix-z13-touchpad.sh.

if omarchy-hw-t2; then
  echo "Detected T2 Mac. Marking the built-in trackpad as internal."

  src="$OMARCHY_INSTALL/hardware/apple"
  rule_dst="${OMARCHY_T2_TOUCHPAD_RULE:-/etc/udev/rules.d/99-omarchy-t2-touchpad.rules}"

  install -Dm644 "$src/99-omarchy-t2-touchpad.rules" "$rule_dst"
fi
