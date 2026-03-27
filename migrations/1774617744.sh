echo "Fix suspend/sleep on T2 MacBooks"

# Only run on T2 Macs
if ! lspci -nn | grep -q "106b:180[12]"; then
  exit 0
fi

# Force s2idle (freeze) suspend mode — T2 Macs cannot use S3 (deep) sleep
sudo mkdir -p /etc/systemd/sleep.conf.d
cat <<EOF | sudo tee /etc/systemd/sleep.conf.d/t2-suspend.conf >/dev/null
[Sleep]
SuspendState=freeze
EOF

# Add mem_sleep_default=s2idle to kernel cmdline if not present
T2_CONF="/etc/limine-entry-tool.d/t2-mac.conf"
if [[ -f "$T2_CONF" ]] && ! grep -q "mem_sleep_default=s2idle" "$T2_CONF"; then
  sudo sed -i 's/pcie_ports=compat"/pcie_ports=compat mem_sleep_default=s2idle"/' "$T2_CONF"
fi

# Regenerate boot config so kernel cmdline change takes effect
if command -v limine-mkinitcpio >/dev/null 2>&1; then
  sudo limine-mkinitcpio
fi

# Create and enable suspend service if not already present
if [[ ! -f /etc/systemd/system/omarchy-suspend-t2.service ]]; then
  cat <<'EOF' | sudo tee /etc/systemd/system/omarchy-suspend-t2.service >/dev/null
[Unit]
Description=Manage T2 modules around suspend
Before=sleep.target
StopWhenUnneeded=yes

[Service]
User=root
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'for dev in /sys/bus/pci/devices/*/; do vendor=$(cat "$dev/vendor" 2>/dev/null); device=$(cat "$dev/device" 2>/dev/null); if [[ "$vendor" == "0x106b" ]] && [[ "$device" == "0x2005" || "$device" == "0x1801" || "$device" == "0x1802" ]]; then echo 0 > "$dev/d3cold_allowed" 2>/dev/null; fi; done; rmmod brcmfmac_wcc 2>/dev/null; rmmod brcmfmac 2>/dev/null; rmmod -f apple-bce 2>/dev/null'
ExecStop=/bin/bash -c 'modprobe apple-bce; sleep 2; modprobe brcmfmac'

[Install]
WantedBy=sleep.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable omarchy-suspend-t2.service
fi

# Clean up old user-created suspend-t2.service (pre-omarchy naming)
if [[ -f /etc/systemd/system/suspend-t2.service ]]; then
  sudo systemctl disable suspend-t2.service 2>/dev/null
  sudo rm -f /etc/systemd/system/suspend-t2.service
  sudo systemctl daemon-reload
fi
