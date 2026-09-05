echo "Restart Bluetooth agent so pairing can show a keyboard passkey"

# omarchy-bluetooth-agent talks to BlueZ through python-dbus. The ISO pacstraps
# it from omarchy-base.packages, but an existing install only gets it here.
# Restarting the unit without it would fail on import and loop every two
# seconds, so let a failed install stop this migration and keep it pending.
omarchy-pkg-add python-dbus

# The packaged unit now starts omarchy-bluetooth-agent instead of
# bt-agent -c NoInputNoOutput. Reload so the user manager picks up the
# new ExecStart, then bounce a live agent. Login starts it for everyone else.
systemctl --user daemon-reload >/dev/null 2>&1 || true

if systemctl --user is-enabled --quiet bt-agent.service 2>/dev/null; then
  systemctl --user reset-failed bt-agent.service 2>/dev/null || true
  systemctl --user restart bt-agent.service || true
fi
