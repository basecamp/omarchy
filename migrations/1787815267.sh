echo "Restart the Bluetooth pairing agent so it waits for late USB adapters"

# The packaged unit used to skip forever when /sys/class/bluetooth was missing
# at graphical-session start (Broadcom on Intel MacBooks, USB dongles). Reload
# so the user manager picks up the wait-then-exec wrapper, then bounce a live
# or skipped agent. Login starts it for everyone else.
systemctl --user daemon-reload

if systemctl --user is-enabled --quiet bt-agent.service 2>/dev/null; then
  systemctl --user reset-failed bt-agent.service 2>/dev/null || true
  systemctl --user restart bt-agent.service || true
fi
