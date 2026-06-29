# Fix intermittent suspend hang on T2 MacBooks caused by async device suspend.
#
# On T2 Macs the kernel default of asynchronous (parallel) device suspend
# (/sys/power/pm_async=1) intermittently HARD-HANGS the machine the instant it
# enters suspend: black screen, dead keyboard/trackpad/Touch Bar, no wake, only
# a forced power-off recovers. pm_trace fingerprints the hang in the async
# device-suspend core (drivers/base/power/main.c), not in any single driver.
# Forcing synchronous device suspend serialises it and resolves the hang.
#
# Confirmed on MacBookPro16,2 (5/5 clean suspend cycles with the fix vs 5/5
# hangs without). Independent of suspend mode (deep or s2idle). See
# basecamp/omarchy#1840 for the broader set of affected T2 models.
if lspci -nn | grep -q "106b:180[12]"; then
  echo "Detected MacBook with T2 chip. Applying synchronous device-suspend fix..."

  cat <<EOF | sudo tee /etc/systemd/system/omarchy-pm-async-suspend-fix.service >/dev/null
[Unit]
Description=Omarchy synchronous device-suspend fix for T2 MacBook

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo 0 > /sys/power/pm_async'

[Install]
WantedBy=multi-user.target
EOF

  chrootable_systemctl_enable omarchy-pm-async-suspend-fix.service
  sudo systemctl daemon-reload
fi
