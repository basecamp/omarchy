echo "Make Apple Magic Trackpad pointer feel closer to macOS"

# Install-time quirk only reaches machines set up after it shipped. See
# install/hardware/apple/fix-magic-trackpad.sh for why hid-magicmouse kernel
# emulation and the stock libinput size range fight a resting thumb.
source "$OMARCHY_PATH/install/hardware/apple/fix-magic-trackpad.sh"

modprobe_conf="${OMARCHY_HID_MAGICMOUSE_CONF:-/etc/modprobe.d/omarchy-magic-trackpad.conf}"
sysfs="${OMARCHY_HID_MAGICMOUSE_SYSFS:-/sys/module/hid_magicmouse/parameters}"

# The module reads modprobe.d on load. Applying the same values to sysfs makes
# a currently connected trackpad pick them up without a reboot. Magic Mouse
# installs never write the conf, so they are not touched here either.
if [[ -f $modprobe_conf && -f $sysfs/emulate_scroll_wheel ]]; then
  if (( EUID == 0 )); then
    printf 'N\n' >"$sysfs/emulate_scroll_wheel"
    printf 'N\n' >"$sysfs/emulate_3button"
    printf 'N\n' >"$sysfs/scroll_acceleration"
  else
    printf 'N\n' | sudo tee "$sysfs/emulate_scroll_wheel" >/dev/null
    printf 'N\n' | sudo tee "$sysfs/emulate_3button" >/dev/null
    printf 'N\n' | sudo tee "$sysfs/scroll_acceleration" >/dev/null
  fi
fi
