echo "Early-load the Apple HID drivers so the trackpad survives the boot race"

# install/hardware/apple/fix-asahi-hid-race.sh runs on new installs only, so
# machines already installed keep losing the trackpad on unlucky boots until
# this runs it. See docs/apple-silicon-trackpad.md.
OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
hid_race_script="$OMARCHY_PATH/install/hardware/apple/fix-asahi-hid-race.sh"
conf="${OMARCHY_APPLE_HID_CONF:-/etc/mkinitcpio.conf.d/apple_hid_modules.conf}"
ready="${OMARCHY_APPLE_HID_READY:-/var/lib/omarchy/apple-hid-initramfs-ready}"

[[ -f $hid_race_script ]] || exit 0

# The machine-wide marker makes this idempotent across users while still
# distinguishing a written drop-in from a successful initramfs rebuild.
[[ -f $ready ]] && exit 0

# The leaf carries both the hardware gate and the drop-in content; sourcing it
# keeps that to one copy. Anything that is not an Apple Silicon Mac writes
# nothing and falls out below.
[[ -f $conf ]] || source "$hid_race_script"
[[ -f $conf ]] || exit 0

# MODULES reaches the boot only through a rebuilt initramfs, so the drop-in on
# its own would look applied and change nothing.
echo "Rebuilding the initramfs so the Apple HID drivers load early"
if ! sudo mkinitcpio -P; then
  echo "mkinitcpio failed; the Apple HID migration will retry later." >&2
  exit 1
fi

omarchy-state set reboot-required
sudo install -Dm644 /dev/null "$ready"
