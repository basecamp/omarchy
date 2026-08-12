echo "Fix QEMU binfmt registration so sudo works in emulated Docker cross-arch builds"

OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
binfmt_config_script="$OMARCHY_PATH/install/config/binfmt.sh"
binfmt_source_dir="${OMARCHY_BINFMT_SOURCE_DIR:-/usr/lib/binfmt.d}"
binfmt_dir="${OMARCHY_BINFMT_DIR:-/etc/binfmt.d}"

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

[[ -f $binfmt_config_script ]] || exit 0

# Check every architecture the package itself registers, not just one, so an
# architecture added by a later package update still gets fixed.
needs_fix=0
for conf in "$binfmt_source_dir"/qemu-*-static.conf; do
  [[ -e $conf ]] || continue
  grep -q ':OCF$' "$binfmt_dir/$(basename "$conf")" 2>/dev/null || {
    needs_fix=1
    break
  }
done
(( needs_fix )) || exit 0

as_root bash -euo pipefail "$binfmt_config_script"
as_root systemctl restart systemd-binfmt.service
