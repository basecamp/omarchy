echo "Isolate /var/lib/docker on its own Btrfs subvolume so root Snapper rollbacks leave container data alone"

# Machine-wide: one apply per install. The helper is idempotent if another user
# already ran it, but the marker keeps every user's migration state aligned with
# the rest of omarchy-migrate.
machine_marker="${OMARCHY_DOCKER_SUBVOL_MIGRATION_MARKER:-/var/lib/omarchy/migrations/1788028303}"

[[ ! -e $machine_marker ]] || exit 0

if [[ $(findmnt -no FSTYPE / 2>/dev/null) != btrfs ]]; then
  sudo mkdir -p "$(dirname "$machine_marker")"
  sudo touch "$machine_marker"
  exit 0
fi

# Only the stock Omarchy layout (root mounted as subvol=@) gets the isolation.
# Other layouts are left alone rather than inventing a mount scheme for them.
if ! findmnt -no OPTIONS / | grep -q 'subvol=/@\(,\|$\)'; then
  sudo mkdir -p "$(dirname "$machine_marker")"
  sudo touch "$machine_marker"
  exit 0
fi

if omarchy-cmd-missing omarchy-btrfs-isolate-docker; then
  echo "omarchy-btrfs-isolate-docker is not available yet; skip until the next update ships it" >&2
  exit 0
fi

# --migrate moves an existing tree (typical after docker has already run). Fresh
# installs that never started docker take the empty path inside the helper.
sudo omarchy-btrfs-isolate-docker --migrate

sudo mkdir -p "$(dirname "$machine_marker")"
sudo touch "$machine_marker"
