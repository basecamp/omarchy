echo "Configure locate to skip Btrfs snapshots and index Btrfs subvolumes"

OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
locate_config_script=/usr/share/omarchy/install/config/locate.sh
if [[ ! -f $locate_config_script ]]; then
  locate_config_script="$OMARCHY_PATH/install/config/locate.sh"
fi

UPDATEDB_CONF_PATH="${OMARCHY_UPDATEDB_CONF_PATH:-/etc/updatedb.conf}"

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

[[ -f $UPDATEDB_CONF_PATH ]] || exit 0

if grep -q '^PRUNE_BIND_MOUNTS = "no"' "$UPDATEDB_CONF_PATH" &&
  grep -E '^PRUNEPATHS' "$UPDATEDB_CONF_PATH" | grep -qF '/.snapshots'; then
  exit 0
fi

as_root env OMARCHY_UPDATEDB_CONF_PATH="$UPDATEDB_CONF_PATH" bash -euo pipefail "$locate_config_script"

# Rebuild the index with the new exclusions; pruning /.snapshots turns
# multi-hour runs on snapshot-heavy systems back into one-minute runs.
as_root systemctl start --no-block plocate-updatedb.service >/dev/null 2>&1 || true
