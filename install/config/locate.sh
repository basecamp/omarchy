UPDATEDB_CONF_PATH="${OMARCHY_UPDATEDB_CONF_PATH:-/etc/updatedb.conf}"

echo "Configuring locate to skip Btrfs snapshots and index Btrfs subvolumes"

[[ -f $UPDATEDB_CONF_PATH ]] || exit 0

# Btrfs subvolume mounts (like /home) look like bind mounts, so pruning
# bind mounts leaves them out of the index entirely.
if grep -qE '^PRUNE_BIND_MOUNTS[[:space:]]*=' "$UPDATEDB_CONF_PATH"; then
  sed -i -E 's|^PRUNE_BIND_MOUNTS[[:space:]]*=.*|PRUNE_BIND_MOUNTS = "no"|' "$UPDATEDB_CONF_PATH"
else
  printf '%s\n' 'PRUNE_BIND_MOUNTS = "no"' >>"$UPDATEDB_CONF_PATH"
fi

# Snapper snapshots are nested subvolumes reached by plain directory
# traversal, so without this updatedb indexes the system once per snapshot.
# The quotes are optional in updatedb.conf, so read the paths back out of
# whatever quoting the file uses and write the setting in one canonical form.
pruned=$(sed -nE 's|^PRUNEPATHS[[:space:]]*=[[:space:]]*"?([^"]*)"?[[:space:]]*$|\1|p' "$UPDATEDB_CONF_PATH" | tail -n 1)

if [[ " $pruned " != *" /.snapshots "* ]]; then
  if [[ -n $pruned ]]; then
    sed -i -E "s|^PRUNEPATHS[[:space:]]*=.*|PRUNEPATHS = \"/.snapshots $pruned\"|" "$UPDATEDB_CONF_PATH"
  else
    printf '%s\n' 'PRUNEPATHS = "/.snapshots"' >>"$UPDATEDB_CONF_PATH"
  fi
fi
