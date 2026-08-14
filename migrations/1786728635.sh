echo "Restart Bluetooth agent so pairing can show a keyboard passkey"

# The packaged unit now starts omarchy-bluetooth-agent instead of
# bt-agent -c NoInputNoOutput. Reload so the user manager picks up the
# new ExecStart, then bounce a live agent. Login starts it for everyone else.
systemctl --user daemon-reload

if systemctl --user is-enabled --quiet bt-agent.service 2>/dev/null; then
  systemctl --user reset-failed bt-agent.service 2>/dev/null || true
  systemctl --user restart bt-agent.service || true
fi
