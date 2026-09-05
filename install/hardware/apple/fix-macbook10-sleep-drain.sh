# The 2017 12-inch MacBook (MacBook10,1) leaks around a third of a watt in S3.
# ACPI leaves Airport (ARPT / BCM4350) armed as a wake source, which keeps the
# radio powered for the whole sleep. Disable that wakeup.
#
# Do not switch the lid to suspend-then-hibernate. On this chassis hibernate
# never reached S4: the session lock came up and applespi stopped delivering
# keyboard and trackpad events, so the only recovery was a force reboot.

if omarchy-hw-match "MacBook10,1"; then
  echo "Detected MacBook10,1; disabling Wi-Fi wakeup for S3"

  udev_rules=${OMARCHY_MACBOOK10_SLEEP_UDEV:-/etc/udev/rules.d/99-omarchy-macbook10-wifi-wakeup.rules}
  unit_path=${OMARCHY_MACBOOK10_SLEEP_UNIT:-/etc/systemd/system/omarchy-macbook10-sleep-drain.service}
  sleep_hook=${OMARCHY_MACBOOK10_SLEEP_HOOK:-/usr/lib/systemd/system-sleep/omarchy-macbook10-sleep-drain}
  drain_bin=${OMARCHY_MACBOOK10_SLEEP_BIN:-${OMARCHY_PATH:-/usr/share/omarchy}/bin/omarchy-hw-macbook10-sleep-drain}
  logind_dropin=${OMARCHY_MACBOOK10_SLEEP_LOGIND:-/etc/systemd/logind.conf.d/30-macbook10-suspend-then-hibernate.conf}
  sleep_dropin=${OMARCHY_MACBOOK10_SLEEP_CONF:-/etc/systemd/sleep.conf.d/30-macbook10-hibernate-delay.conf}

  sudo mkdir -p "$(dirname "$udev_rules")" "$(dirname "$unit_path")" "$(dirname "$sleep_hook")"

  sudo tee "$udev_rules" >/dev/null <<'EOF'
# BCM4350 on MacBook10,1. Wake-on-WLAN keeps the radio powered through S3.
ACTION=="add|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x14e4", ATTR{device}=="0x43a3", TEST=="power/wakeup", ATTR{power/wakeup}="disabled"
EOF

  sudo tee "$unit_path" >/dev/null <<EOF
[Unit]
Description=Omarchy MacBook10,1 Wi-Fi wakeup disable for S3

[Service]
Type=oneshot
ExecStart=$drain_bin

[Install]
WantedBy=multi-user.target
EOF

  sudo tee "$sleep_hook" >/dev/null <<EOF
#!/bin/bash
exec "$drain_bin"
EOF
  sudo chmod 755 "$sleep_hook"

  sudo rm -f "$logind_dropin" "$sleep_dropin"
  sudo systemctl reload systemd-logind >/dev/null 2>&1 || true

  sudo systemctl daemon-reload
  sudo systemctl enable --now omarchy-macbook10-sleep-drain.service
fi
