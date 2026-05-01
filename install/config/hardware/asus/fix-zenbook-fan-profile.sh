if omarchy-hw-match "Zenbook"; then
  sudo tee /etc/sudoers.d/omarchy-zenbook-fan-profile >/dev/null << EOF
$USER ALL=(root) NOPASSWD: /usr/bin/tee /sys/firmware/acpi/platform_profile
EOF
  sudo chmod 440 /etc/sudoers.d/omarchy-zenbook-fan-profile
fi
