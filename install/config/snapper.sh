SNAPPER_CONFIG_PATH="${OMARCHY_SNAPPER_CONFIG_PATH:-/etc/snapper/configs/root}"
SNAPPER_CONF_PATH="${OMARCHY_SNAPPER_CONF_PATH:-/etc/conf.d/snapper}"
template="${OMARCHY_SNAPPER_TEMPLATE:-${OMARCHY_PATH:-/usr/share/omarchy}/default/snapper/root}"

# Recovery snapshots are filesystem-specific. Btrfs has native subvolumes, so
# Snapper and Limine snapshot boot entries work; any other filesystem falls
# back to rsync snapshots through Timeshift and keeps Snapper disabled. Allow
# tests to pin the detection.
root_fstype="${OMARCHY_SNAPPER_FSTYPE:-$(findmnt -no FSTYPE / 2>/dev/null || true)}"

if [[ $root_fstype == "btrfs" ]]; then
  echo "Configuring Omarchy Snapper snapshot retention"

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
else
  echo "Root is $root_fstype, not Btrfs: skipping Snapper and Limine snapshot sync"

  # Snapper and limine-snapper-sync only understand Btrfs subvolumes. Earlier
  # setup wrote an impossible FSTYPE="btrfs" root config on non-Btrfs roots,
  # making snapper-cleanup fail every night and the pre-update snapshot abort
  # (#6683). Remove the phantom config and its SNAPPER_CONFIGS entry.
  if [[ -f $SNAPPER_CONFIG_PATH ]] &&
    grep -qFx 'FSTYPE="btrfs"' "$SNAPPER_CONFIG_PATH"; then
    rm -f "$SNAPPER_CONFIG_PATH"
  fi

  mkdir -p "$(dirname "$SNAPPER_CONF_PATH")"
  printf '%s\n' 'SNAPPER_CONFIGS=""' >"$SNAPPER_CONF_PATH"
  chmod 0644 "$SNAPPER_CONF_PATH"

  # Nothing to clean or sync without Btrfs; keep the units from failing daily.
  systemctl disable --now snapper-cleanup.timer >/dev/null 2>&1 || true
  systemctl disable --now limine-snapper-sync.service >/dev/null 2>&1 || true
fi
