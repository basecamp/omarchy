echo "Remove Btrfs snapshot setup from non-Btrfs roots"

[[ $(findmnt -no FSTYPE /) != "btrfs" ]] || exit 0

snapper_config_script="$OMARCHY_PATH/install/config/snapper.sh"

if (( EUID == 0 )); then
  env OMARCHY_PATH="$OMARCHY_PATH" bash -euo pipefail "$snapper_config_script"
else
  sudo env OMARCHY_PATH="$OMARCHY_PATH" bash -euo pipefail "$snapper_config_script"
fi
