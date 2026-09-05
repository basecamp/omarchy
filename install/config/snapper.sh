SNAPPER_CONFIG_PATH="${OMARCHY_SNAPPER_CONFIG_PATH:-/etc/snapper/configs/root}"
SNAPPER_CONF_PATH="${OMARCHY_SNAPPER_CONF_PATH:-/etc/conf.d/snapper}"
template="${OMARCHY_SNAPPER_TEMPLATE:-${OMARCHY_PATH:-/usr/share/omarchy}/default/snapper/root}"

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

# Merge SNAPPER_CONFIGS so a prior user config (commonly "home" on @/@home
# layouts) is not silently dropped. root is always first and always present;
# every other existing entry is preserved in order without duplicating root.
mkdir -p "$(dirname "$SNAPPER_CONF_PATH")"
existing=""
if [[ -f $SNAPPER_CONF_PATH ]]; then
  # conf.d/snapper is KEY=value assignments; source only to read SNAPPER_CONFIGS.
  existing="$(
    # shellcheck disable=SC1090
    . "$SNAPPER_CONF_PATH" 2>/dev/null
    printf '%s' "${SNAPPER_CONFIGS:-}"
  )"
fi
merged="root"
for config in $existing; do
  if [[ $config != "root" ]]; then
    merged+=" $config"
  fi
done
printf 'SNAPPER_CONFIGS="%s"\n' "$merged" >"$SNAPPER_CONF_PATH"
chmod 0644 "$SNAPPER_CONF_PATH"

systemctl disable --now snapper-timeline.timer >/dev/null 2>&1 || true
systemctl enable --now snapper-cleanup.timer limine-snapper-sync.service >/dev/null 2>&1 || true
