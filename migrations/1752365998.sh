echo "Add override to only require one network interface to be online"

if [[ ! -f /etc/systemd/system/systemd-networkd-wait-online.service.d/wait-for-only-one-interface.conf ]]; then
  sudo mkdir -p /etc/systemd/system/systemd-networkd-wait-online.service.d
  sudo tee /etc/systemd/system/systemd-networkd-wait-online.service.d/wait-for-only-one-interface.conf >/dev/null <<EOF
[Service]
ExecStart=
ExecStart=/usr/lib/systemd/systemd-networkd-wait-online --any
EOF
fi
