# Update localdb so that locate will find everything installed

UPDATEDB_CONF="/etc/updatedb.conf"

if [[ -f "$UPDATEDB_CONF" ]]; then
  # Ensure /home (and other non-pruned mounts) are included in the locate database by default.
  # Be tolerant of whitespace: PRUNE_BIND_MOUNTS = "yes" / PRUNE_BIND_MOUNTS="yes" / etc.
  if grep -qE '^[[:space:]]*PRUNE_BIND_MOUNTS[[:space:]]*=' "$UPDATEDB_CONF"; then
    sudo sed -i -E 's|^[[:space:]]*PRUNE_BIND_MOUNTS[[:space:]]*=.*$|PRUNE_BIND_MOUNTS = "no"|' "$UPDATEDB_CONF"
  else
    echo 'PRUNE_BIND_MOUNTS = "no"' | sudo tee -a "$UPDATEDB_CONF" >/dev/null
  fi
else
  echo "Warning: $UPDATEDB_CONF not found; skipping PRUNE_BIND_MOUNTS configuration" >&2
fi

sudo updatedb
