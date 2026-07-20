echo "Stop waiting for the network before showing the desktop"

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

# graphical.target was gated on network-online.target (cups-browsed orders
# itself after it), so the desktop waited for DHCP/Wi-Fi association at boot.
# Nothing in the session needs to block on the network; mask the wait so
# network-online no longer delays boot. Mirrors the systemd-networkd variant.
as_root systemctl mask NetworkManager-wait-online.service >/dev/null 2>&1 || true
