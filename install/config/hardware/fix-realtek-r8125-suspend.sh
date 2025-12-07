if lspci -nn | grep -q "10ec:8125"; then
  sudo mkdir -p /usr/lib/systemd/system-sleep
  cat <<'EOF' | sudo tee /usr/lib/systemd/system-sleep/omarchy-r8125-resume.sh >/dev/null
#!/bin/bash
if [[ "$1" != "post" ]]; then
  exit 0
fi

for iface in /sys/class/net/*; do
  ifname=$(basename "$iface")
  if [[ "$ifname" == "lo" ]]; then
    continue
  fi

  driver=$(basename "$(readlink "$iface/device/driver" 2>/dev/null)" 2>/dev/null)
  if [[ "$driver" != "r8169" ]] && [[ "$driver" != "r8125" ]]; then
    continue
  fi

  ip link set "$ifname" down 2>/dev/null && ip link set "$ifname" up 2>/dev/null
done
EOF
  sudo chmod +x /usr/lib/systemd/system-sleep/omarchy-r8125-resume.sh
fi
