UPDATEDB_CONF_PATH="${OMARCHY_UPDATEDB_CONF_PATH:-/etc/updatedb.conf}"

echo "Configuring locate to skip Btrfs snapshots and index Btrfs subvolumes"

[[ -f $UPDATEDB_CONF_PATH ]] || exit 0

# updatedb refuses to run at all on a config that defines a variable twice, so
# every setting here is rewritten where it already stands and only appended
# when the file has no line for it.

# Btrfs subvolume mounts (like /home) look like bind mounts, so pruning
# bind mounts leaves them out of the index entirely.
if grep -qE '^[[:space:]]*PRUNE_BIND_MOUNTS[[:space:]]*=' "$UPDATEDB_CONF_PATH"; then
  sed -i -E 's|^[[:space:]]*PRUNE_BIND_MOUNTS[[:space:]]*=.*|PRUNE_BIND_MOUNTS = "no"|' "$UPDATEDB_CONF_PATH"
else
  printf '%s\n' 'PRUNE_BIND_MOUNTS = "no"' >>"$UPDATEDB_CONF_PATH"
fi

# Snapper snapshots are nested subvolumes reached by plain directory
# traversal, so without this updatedb indexes the system once per snapshot.
if grep -qE '^[[:space:]]*PRUNEPATHS[[:space:]]*=' "$UPDATEDB_CONF_PATH"; then
  # updatedb only accepts quoted values and allows a comment after them. Read
  # back what the machine already prunes and write the whole setting out again
  # rather than splicing into a line of unknown shape.
  pruned=$(sed -nE 's|^[[:space:]]*PRUNEPATHS[[:space:]]*=[[:space:]]*"([^"]*)".*|\1|p' "$UPDATEDB_CONF_PATH" | tail -n 1)

  if [[ " $pruned " != *" /.snapshots "* ]]; then
    sed -i -E "s|^[[:space:]]*PRUNEPATHS[[:space:]]*=.*|PRUNEPATHS = \"/.snapshots${pruned:+ $pruned}\"|" "$UPDATEDB_CONF_PATH"
  fi
else
  printf '%s\n' 'PRUNEPATHS = "/.snapshots"' >>"$UPDATEDB_CONF_PATH"
fi
