echo "Enable Thunderbolt auto-authorization"

# Auto-authorize Thunderbolt devices on hotplug
if [ ! -f /etc/udev/rules.d/99-thunderbolt.rules ]; then
  sudo tee /etc/udev/rules.d/99-thunderbolt.rules > /dev/null <<'EOF'
ACTION=="add", SUBSYSTEM=="thunderbolt", ATTR{authorized}=="0", \
  RUN+="/bin/sh -c 'echo 1 > /sys$devpath/authorized'"
EOF

  # Reload and trigger udev for immediate effect
  sudo udevadm control --reload
  sudo udevadm trigger --subsystem-match=thunderbolt || true
fi