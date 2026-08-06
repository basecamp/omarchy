SNAPPER_CONFIG_PATH="${OMARCHY_SNAPPER_CONFIG_PATH:-/etc/snapper/configs/root}"
SNAPPER_CONF_PATH="${OMARCHY_SNAPPER_CONF_PATH:-/etc/conf.d/snapper}"
template="${OMARCHY_SNAPPER_TEMPLATE:-${OMARCHY_PATH:-/usr/share/omarchy}/default/snapper/root}"
root_fstype="${OMARCHY_SNAPPER_ROOT_FSTYPE:-$(findmnt -no FSTYPE --target / 2>/dev/null || true)}"

echo "Configuring Omarchy Snapper snapshot retention"

# snapper create-config only works on a filesystem it supports, which for Omarchy
# means btrfs. On any other root it fails with "Creating config failed
# (/sbin/chsnap not installed)", and every caller runs this under
# bash -euo pipefail, so that failure aborts omarchy-upgrade-to-quattro partway
# through and stops migration 1781984677 along with every migration queued behind
# it. Nothing below this point means anything without a config, so skip cleanly.
if [[ $root_fstype != "btrfs" ]]; then
  echo "Root filesystem is ${root_fstype:-unknown}, not btrfs: skipping Snapper configuration"
  exit 0
fi

if [[ ! -f $SNAPPER_CONFIG_PATH ]]; then
  mkdir -p "$(dirname "$SNAPPER_CONFIG_PATH")"

  if [[ ${OMARCHY_SNAPPER_CONFIGURE_TEST:-0} == "1" ]]; then
    : >"$SNAPPER_CONFIG_PATH"
  else
    snapper --no-dbus -c root create-config / >/dev/null 2>&1 || snapper -c root create-config / >/dev/null
  fi
fi

install -m 0644 "$template" "$SNAPPER_CONFIG_PATH"

mkdir -p "$(dirname "$SNAPPER_CONF_PATH")"
printf '%s\n' 'SNAPPER_CONFIGS="root"' >"$SNAPPER_CONF_PATH"
chmod 0644 "$SNAPPER_CONF_PATH"

systemctl disable --now snapper-timeline.timer >/dev/null 2>&1 || true
systemctl enable --now snapper-cleanup.timer limine-snapper-sync.service >/dev/null 2>&1 || true
