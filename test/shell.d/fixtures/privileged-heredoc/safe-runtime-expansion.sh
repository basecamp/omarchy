# \$TERM stays literal so systemd expands it at runtime; nothing is baked in.
cat <<EOF | sudo tee /etc/systemd/system/getty@tty1.service.d/override.conf >/dev/null
[Service]
Environment=TERM=\$TERM
ExecStart=-/usr/bin/agetty --noclear %I \$TERM
EOF
