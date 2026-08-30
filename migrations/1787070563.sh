echo "Prepare non-Btrfs roots for Omarchy snapshot recovery via Timeshift"

# Snapper and limine-snapper-sync only understand Btrfs subvolumes. Setup used
# to write an impossible FSTYPE="btrfs" root config on every filesystem, which
# made snapper-cleanup fail nightly and aborted the pre-update snapshot on
# non-Btrfs roots (#6683). Machine-wide repairs happen once per user, so check
# the actual root filesystem before touching anything and no-op elsewhere.

OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
snapper_config_script="$OMARCHY_PATH/install/config/snapper.sh"

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

root_fstype=$(findmnt -no FSTYPE / 2>/dev/null || true)

if [[ $root_fstype != "btrfs" ]] && [[ -f "$snapper_config_script" ]]; then
  as_root env OMARCHY_PATH="$OMARCHY_PATH" bash -euo pipefail "$snapper_config_script"
fi