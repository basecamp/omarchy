# Apple Magic Trackpad: closer to macOS pointer feel.
#
# hid-magicmouse turns a resting thumb plus one moving finger into two-finger
# scroll or a right-click. libinput can ignore that thumb, but only if the
# kernel stops emulating those gestures first. Stock libinput quirks also set
# AttrTouchSizeRange=20:10 on these pads, which disables size-based palm/thumb
# filtering.
#
# The same kernel module drives Magic Mouse, whose touch-surface scroll depends
# on emulate_scroll_wheel, so the module options are skipped when a Magic Mouse
# is present. The libinput quirks match Magic Trackpad devices by name and
# are safe to install always.

quirks="${OMARCHY_MAGIC_TRACKPAD_QUIRKS:-/etc/libinput/omarchy-magic-trackpad.quirks}"
modprobe_conf="${OMARCHY_HID_MAGICMOUSE_CONF:-/etc/modprobe.d/omarchy-magic-trackpad.conf}"

write_file() {
  local dest=$1
  if (( EUID == 0 )); then
    mkdir -p "$(dirname "$dest")"
    cat >"$dest"
  else
    sudo mkdir -p "$(dirname "$dest")"
    sudo tee "$dest" >/dev/null
  fi
}

write_file "$quirks" <<'EOF'
# Omarchy: ignore a light resting thumb on Apple Magic Trackpad.
# Stock libinput 50-system-apple.quirks uses AttrTouchSizeRange=20:10, which
# turns size-based palm/thumb filtering off and trusts device firmware.
[Apple Magic Trackpad]
MatchName=*Magic Trackpad*
MatchUdevType=touchpad
AttrSizeHint=162x115
AttrTouchSizeRange=40:20
AttrThumbSizeThreshold=550
AttrPalmSizeThreshold=750
AttrThumbPressureThreshold=70
AttrPalmPressureThreshold=160
EOF

if omarchy-hw-apple-magic-mouse || ! omarchy-hw-apple-magic-trackpad; then
  return 0
fi

write_file "$modprobe_conf" <<'EOF'
# Let libinput own two-finger scroll and multi-finger clicks on Magic Trackpad.
# hid-magicmouse otherwise treats a resting thumb as a second finger.
# Skipped when a Magic Mouse is present: that device still needs kernel
# surface-scroll emulation.
options hid_magicmouse emulate_scroll_wheel=0 emulate_3button=0 scroll_acceleration=0
EOF
