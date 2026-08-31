echo "Keep the GETAC V110G3 Synaptics touchpad alive across S3 resume"

omarchy-hw-getac-v110g3 || exit 0

source "$OMARCHY_PATH/install/hardware/getac/fix-v110g3-touchpad.sh"

omarchy-cmd-present limine-mkinitcpio || exit 0

rebuild_marker="${OMARCHY_GETAC_V110G3_REBUILD_MARKER:-/var/lib/omarchy/migrations/1788129995}"
[[ ! -e $rebuild_marker ]] || exit 0

sudo limine-mkinitcpio
sudo install -Dm644 /dev/null "$rebuild_marker"
omarchy-state set reboot-required
