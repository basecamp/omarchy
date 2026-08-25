echo "Disable USB autosuspend on the kernel cmdline"

# usbcore is built into the Arch kernel, so the old modprobe.d drop-in never
# applied and autosuspend stayed at the default of 2. Put the parameter on the
# Limine command line, where built-in usbcore reads it. Fresh installs get the
# same line from the packaged omarchy-defaults.conf. Append only: do not rewrite
# KERNEL_CMDLINE, or cryptdevice/root from other drop-ins would be lost.

defaults_conf="${OMARCHY_LIMINE_DEFAULTS_CONF:-/etc/limine-entry-tool.d/omarchy-defaults.conf}"
running_cmdline="${OMARCHY_RUNNING_CMDLINE:-/proc/cmdline}"
rebuild_marker="${OMARCHY_USB_AUTOSUSPEND_REBUILD_MARKER:-/var/lib/omarchy/migrations/1787601557}"
modprobe_conf="${OMARCHY_USB_AUTOSUSPEND_MODPROBE:-/etc/modprobe.d/omarchy-usb-autosuspend.conf}"

if [[ -e $modprobe_conf ]]; then
  sudo rm -f "$modprobe_conf"
fi

omarchy-cmd-present limine-mkinitcpio || exit 0
[[ -f $defaults_conf ]] || exit 0

if ! grep -Fq 'usbcore.autosuspend' "$defaults_conf"; then
  echo 'KERNEL_CMDLINE[default]+=" usbcore.autosuspend=-1"' |
    sudo tee -a "$defaults_conf" >/dev/null
fi

# The running kernel keeps its old command line until reboot, so a marker
# records the machine-wide rebuild instead: another user's migration must not
# repeat it before then, while a missing marker still retries an interrupted
# rebuild.
[[ ! -e $rebuild_marker ]] || exit 0
[[ -r $running_cmdline ]] || exit 0
grep -Fq 'usbcore.autosuspend=-1' "$defaults_conf" || exit 0

booted=$(<"$running_cmdline")
if [[ " $booted " == *" usbcore.autosuspend=-1 "* ]]; then
  exit 0
fi

echo "The booted kernel is missing usbcore.autosuspend=-1; rebuilding the boot image"
sudo limine-mkinitcpio
sudo install -Dm644 /dev/null "$rebuild_marker"
