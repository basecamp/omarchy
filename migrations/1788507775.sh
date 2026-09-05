echo "Apply Omarchy's USB autosuspend policy through the kernel command line"

defaults_conf="${OMARCHY_USB_AUTOSUSPEND_DEFAULTS_CONF:-/etc/limine-entry-tool.d/omarchy-defaults.conf}"
legacy_conf="${OMARCHY_USB_AUTOSUSPEND_LEGACY_CONF:-/etc/modprobe.d/omarchy-usb-autosuspend.conf}"
running_cmdline="${OMARCHY_USB_AUTOSUSPEND_RUNNING_CMDLINE:-/proc/cmdline}"
rebuild_marker="${OMARCHY_USB_AUTOSUSPEND_REBUILD_MARKER:-/var/lib/omarchy/migrations/1788507775}"

# Remove only the exact file Omarchy used to ship. Preserve administrator
# changes, even though usbcore is built in and modprobe cannot apply them.
if [[ -f $legacy_conf ]] &&
  [[ $(<"$legacy_conf") == "options usbcore autosuspend=-1" ]]; then
  sudo rm "$legacy_conf"
fi

omarchy-cmd-present limine-mkinitcpio || exit 0
[[ -f $defaults_conf && -r $running_cmdline ]] || exit 0
grep -Fq 'usbcore.autosuspend=-1' "$defaults_conf" || exit 0

# The running command line cannot change until reboot. Record a successful
# rebuild so this machine-wide repair is not repeated for each Omarchy user.
[[ ! -e $rebuild_marker ]] || exit 0

if [[ " $(<"$running_cmdline") " != *" usbcore.autosuspend=-1 "* ]]; then
  sudo limine-mkinitcpio
  sudo install -Dm644 /dev/null "$rebuild_marker"
  omarchy-state set reboot-required
fi
