echo "Stop forcing hid_apple fnmode=2 on genuine Apple keyboards"

# install/hardware/fix-fkeys.sh used to write this on every machine. Auto
# (fnmode=3) already gives APPLE_IS_NON_APPLE boards fkeysfirst, but Lofree
# Flow84 is not on that list, so non-Apple installs keep the drop-in. Apple/T2
# hardware must go back to the kernel default so media keys work without Fn.

dmi_vendor="${OMARCHY_HID_APPLE_DMI_VENDOR:-/sys/class/dmi/id/sys_vendor}"
conf="${OMARCHY_HID_APPLE_CONF:-/etc/modprobe.d/hid_apple.conf}"
sys_vendor="$(cat "$dmi_vendor" 2>/dev/null || true)"

[[ $sys_vendor == Apple* ]] || exit 0
[[ -f $conf ]] || exit 0
[[ $(<"$conf") == "options hid_apple fnmode=2" ]] || exit 0

sudo rm -f "$conf"

# T2 bakes hid_apple into the initramfs, so deleting the live drop-in is not
# enough until that image is rebuilt. Other Apple machines load hid_apple later
# and only need a reboot.
if lspci -nn | grep "106b:180[12]" >/dev/null; then
  if omarchy-cmd-present limine-mkinitcpio; then
    sudo limine-mkinitcpio
  fi
fi

omarchy-state set reboot-required
