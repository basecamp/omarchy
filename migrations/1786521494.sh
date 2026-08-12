echo "Fix QEMU binfmt registration so sudo works in emulated Docker cross-arch builds"

OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
binfmt_config_script="$OMARCHY_PATH/install/config/binfmt.sh"

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

[[ -f $binfmt_config_script ]] || exit 0

grep -q ':OCF$' /etc/binfmt.d/qemu-aarch64-static.conf 2>/dev/null && exit 0

as_root bash -euo pipefail "$binfmt_config_script"
as_root systemctl restart systemd-binfmt.service
