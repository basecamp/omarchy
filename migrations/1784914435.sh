echo "Keep Wi-Fi power save off for lower latency"

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

as_root nmcli general reload conf >/dev/null 2>&1 || true

# NetworkManager only applies wifi.powersave when a connection activates, so
# also switch it off directly for the running session.
shopt -s nullglob
for wireless in /sys/class/net/*/wireless; do
  iface=$(basename "$(dirname "$wireless")")
  as_root iw dev "$iface" set power_save off 2>/dev/null || true
done
