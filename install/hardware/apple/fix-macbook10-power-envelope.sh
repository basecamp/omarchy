# The 2017 12-inch MacBook (MacBook10,1) is fanless. Apple leaves RAPL unlocked,
# so Linux programs a 49W package cap on a 4.5W Y-series part and the i7-7Y75
# turbos to 3.6GHz until the 100°C trip. Cap PL1/PL2 to Intel's TDP / cTDP-up
# and CPU turbo to the m3-7Y32's 3.0GHz so the chassis stays in the envelope
# both SKUs were rated for.

if omarchy-hw-macbook10; then
  echo "Detected MacBook10,1; capping RAPL at 4.5W/7W and CPU turbo at 3GHz"

  unit_path=${OMARCHY_MACBOOK10_ENVELOPE_UNIT:-/etc/systemd/system/omarchy-macbook10-power-envelope.service}
  sleep_hook=${OMARCHY_MACBOOK10_ENVELOPE_SLEEP_HOOK:-/usr/lib/systemd/system-sleep/omarchy-macbook10-power-envelope}
  envelope_bin=${OMARCHY_MACBOOK10_ENVELOPE_BIN:-${OMARCHY_PATH:-/usr/share/omarchy}/bin/omarchy-hw-macbook10-power-envelope}

  sudo mkdir -p "$(dirname "$unit_path")" "$(dirname "$sleep_hook")"

  sudo tee "$unit_path" >/dev/null <<EOF
[Unit]
Description=Omarchy MacBook10,1 RAPL and CPU frequency envelope

[Service]
Type=oneshot
ExecStart=$envelope_bin

[Install]
WantedBy=multi-user.target
EOF

  sudo tee "$sleep_hook" >/dev/null <<EOF
#!/bin/bash
[[ \$1 == post ]] || exit 0
exec "$envelope_bin"
EOF
  sudo chmod 755 "$sleep_hook"

  sudo systemctl daemon-reload
  sudo systemctl enable --now omarchy-macbook10-power-envelope.service
fi
