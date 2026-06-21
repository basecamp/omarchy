# NetworkManager enablement is centralized in enable-services.sh.
systemctl disable iwd.service 2>/dev/null || true

# Fresh Omarchy uses NetworkManager. Archinstall's legacy "copy ISO network"
# mode enabled systemd-networkd and dropped DHCP .network files that compete
# with NetworkManager, so retire that state whenever hardware setup runs.
for unit in \
  systemd-networkd.service \
  systemd-networkd.socket \
  systemd-networkd-varlink.socket \
  systemd-networkd-varlink-metrics.socket \
  systemd-networkd-resolve-hook.socket; do
  systemctl disable "$unit" 2>/dev/null || true
done

# Prevent systemd-networkd-wait-online timeout on boot.
systemctl disable systemd-networkd-wait-online.service 2>/dev/null || true
systemctl mask systemd-networkd-wait-online.service 2>/dev/null || true

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

backup_dir="/etc/systemd/network/omarchy-networkd-retired-$(date +%Y%m%d%H%M%S)"
for file in /etc/systemd/network/20-ethernet.network /etc/systemd/network/20-wlan.network /etc/systemd/network/20-wwan.network; do
  if stock_networkd_file "$file"; then
    install -d -m 0755 "$backup_dir"
    mv "$file" "$backup_dir/"
  fi
done

if systemctl is-active --quiet NetworkManager.service 2>/dev/null; then
  systemctl stop systemd-networkd.service 2>/dev/null || true
fi
