# Prepare T2 Mac peripherals for suspend.
#
# Two devices break suspend on these machines, independently of whether the
# install runs the apple-bce or the t2bce driver stack:
#
#   brcmfmac times out entering D3 (brcmf_pcie_pm_enter_D3, -EIO). The failure
#   propagates out of pci_pm_suspend and aborts the transition, so the machine
#   does not sleep at all: /sys/power/suspend_stats/success stays at zero while
#   fail climbs. Unloading the module before suspend resets the firmware and
#   removes the callback that fails.
#
#   The Apple NVMe controller and the T2 bridges enter d3cold and cannot be
#   brought back out ("Unable to change power state from D3hot to D0, device
#   inaccessible" against the controller hosting the root filesystem). Short
#   sleeps survive it; longer ones do not.
if lspci -nn | grep "106b:180[12]" >/dev/null; then
  echo "Detected MacBook with T2 chip. Configuring suspend..."

  # systemd chooses the suspend state itself and only consults
  # mem_sleep_default when it writes "mem". Pin "freeze" so the choice does not
  # depend on the kernel command line surviving a boot-config regeneration.
  mkdir -p /etc/systemd/sleep.conf.d
  cat > /etc/systemd/sleep.conf.d/t2-suspend.conf <<'EOF'
[Sleep]
SuspendState=freeze
EOF

  cat > /etc/systemd/system/omarchy-suspend-t2.service <<'EOF'
[Unit]
Description=Prepare T2 Mac peripherals for suspend
Before=sleep.target
StopWhenUnneeded=yes

[Service]
User=root
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'for dev in /sys/bus/pci/devices/*/; do vendor=$(cat "$dev/vendor" 2>/dev/null); device=$(cat "$dev/device" 2>/dev/null); if [[ "$vendor" == "0x106b" ]] && [[ "$device" == "0x2005" || "$device" == "0x1801" || "$device" == "0x1802" ]]; then echo 0 > "$dev/d3cold_allowed" 2>/dev/null; fi; done; rmmod brcmfmac_wcc 2>/dev/null; rmmod brcmfmac 2>/dev/null; true'
ExecStop=/bin/bash -c 'modprobe brcmfmac'

[Install]
WantedBy=sleep.target
EOF

  systemctl enable omarchy-suspend-t2.service
fi
