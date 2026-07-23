echo "Remove Snapper timeline snapshots leaked by earlier defaults"

SNAPPER_CONFIG_PATH="${OMARCHY_SNAPPER_CONFIG_PATH:-/etc/snapper/configs/root}"

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

command -v snapper >/dev/null || exit 0
[[ -f $SNAPPER_CONFIG_PATH ]] || exit 0

# Only clean up when timeline snapshotting is off, as Omarchy configures it.
# Anyone who deliberately turned it back on keeps their snapshots.
grep -qFx 'TIMELINE_CREATE="no"' "$SNAPPER_CONFIG_PATH" || exit 0

# Earlier installs ran hourly timeline snapshots. Later configs stopped
# creating them but never deleted the existing ones, and number cleanup
# skips snapshots marked Cleanup=timeline, so they pile up forever:
# hundreds of snapshots pinning 100+ GB of extents on long-running machines.
leaked=$(as_root snapper -c root --csvout list --columns number,cleanup 2>/dev/null | awk -F, '$2 == "timeline" { print $1 }' || true)
[[ -n $leaked ]] || exit 0

echo "Deleting $(wc -w <<<"$leaked") leaked timeline snapshots (disk space is reclaimed in the background)"

# Delete in small batches; one big delete can die on a DBus timeout partway.
# A failed batch must not take the rest of the migration run down with it, so
# the drain is best effort: whatever survives is picked up by the next run.
batch=()
for number in $leaked; do
  batch+=("$number")
  if (( ${#batch[@]} == 20 )); then
    as_root snapper -c root delete "${batch[@]}" || true
    batch=()
  fi
done

if (( ${#batch[@]} > 0 )); then
  as_root snapper -c root delete "${batch[@]}" || true
fi
