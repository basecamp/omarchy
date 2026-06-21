echo "Retire systemd-networkd in favor of NetworkManager"

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

stock_networkd_file() {
  local file="$1"

  [[ -f $file ]] || return 1
  case "$(basename "$file")" in
    20-ethernet.network|20-wlan.network|20-wwan.network) ;;
    *) return 1 ;;
  esac

  grep -Eq '^[[:space:]]*DHCP=yes[[:space:]]*$' "$file" || return 1
  grep -Eq '^[[:space:]]*Name=(en\*|eth\*|wl\*|ww\*)[[:space:]]*$' "$file" || return 1
}

backup_stock_networkd_files() {
  local backup_dir="/etc/systemd/network/omarchy-networkd-retired-$(date +%Y%m%d%H%M%S)"
  local file

  for file in /etc/systemd/network/20-ethernet.network /etc/systemd/network/20-wlan.network /etc/systemd/network/20-wwan.network; do
    if stock_networkd_file "$file"; then
      as_root install -d -m 0755 "$backup_dir"
      as_root mv "$file" "$backup_dir/"
    fi
  done
}

networkd_units=(
  systemd-networkd.service
  systemd-networkd.socket
  systemd-networkd-varlink.socket
  systemd-networkd-varlink-metrics.socket
  systemd-networkd-resolve-hook.socket
)

if [[ ${OMARCHY_UPGRADE_TO_4_LIVE:-0} == "1" ]]; then
  as_root systemctl enable NetworkManager.service >/dev/null 2>&1 || true

  if systemctl is-active --quiet NetworkManager.service 2>/dev/null; then
    # NetworkManager is already carrying the live network; it is safe to stop
    # networkd now so the rest of the upgrade no longer has competing DHCP.
    for unit in "${networkd_units[@]}"; do
      as_root systemctl disable --now "$unit" >/dev/null 2>&1 || true
    done
    as_root systemctl disable systemd-networkd-wait-online.service >/dev/null 2>&1 || true
    as_root systemctl mask systemd-networkd-wait-online.service >/dev/null 2>&1 || true
    backup_stock_networkd_files
    as_root systemctl stop systemd-networkd.service >/dev/null 2>&1 || true
    as_root systemctl reload NetworkManager.service >/dev/null 2>&1 || true
    as_root systemctl restart systemd-resolved.service >/dev/null 2>&1 || true
  else
    # Older live upgrades may still be relying on networkd/iwd. Disable for the
    # next boot, but do not stop or reconfigure the running link.
    for unit in "${networkd_units[@]}"; do
      as_root systemctl disable "$unit" >/dev/null 2>&1 || true
    done
    as_root systemctl disable systemd-networkd-wait-online.service >/dev/null 2>&1 || true
    as_root systemctl mask systemd-networkd-wait-online.service >/dev/null 2>&1 || true
  fi

  exit 0
fi

if ! command -v NetworkManager >/dev/null 2>&1; then
  omarchy-pkg-add networkmanager
fi

as_root systemctl enable --now NetworkManager.service >/dev/null 2>&1 || true

for unit in "${networkd_units[@]}"; do
  as_root systemctl disable --now "$unit" >/dev/null 2>&1 || true
done
as_root systemctl disable systemd-networkd-wait-online.service >/dev/null 2>&1 || true
as_root systemctl mask systemd-networkd-wait-online.service >/dev/null 2>&1 || true

backup_stock_networkd_files
as_root systemctl stop systemd-networkd.service >/dev/null 2>&1 || true

as_root systemctl reload NetworkManager.service >/dev/null 2>&1 || true
as_root systemctl restart systemd-resolved.service >/dev/null 2>&1 || true
