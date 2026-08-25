echo "Stop early-loading the NVIDIA driver on hybrid GPU systems so hibernation can resume"

# install/hardware/nvidia.sh used to write nvidia.conf on every NVIDIA machine.
# On a hybrid laptop the iGPU provides early KMS, and having nvidia already
# loaded inside the initramfs makes resume from hibernation fail with
# "nv_pmops_freeze returns -5" / "PM: hibernation: resume failed (-5)".
# Drop the drop-in on those machines and rebuild the initramfs once. A marker
# records completion so another user's run does not repeat the rebuild.

nvidia_conf="${OMARCHY_MKINITCPIO_NVIDIA_CONF:-/etc/mkinitcpio.conf.d/nvidia.conf}"
rebuild_marker="${OMARCHY_NVIDIA_REBUILD_MARKER:-/var/lib/omarchy/migrations/1787683023}"

omarchy-cmd-present limine-mkinitcpio || exit 0
[[ -f $nvidia_conf ]] || exit 0
[[ ! -e $rebuild_marker ]] || exit 0
omarchy-hw-nvidia-only-display && exit 0

echo "This is a hybrid GPU machine; removing nvidia from the initramfs and rebuilding it"
sudo rm -f "$nvidia_conf"
sudo limine-mkinitcpio
sudo install -Dm644 /dev/null "$rebuild_marker"
