echo "Reconnect trusted Bluetooth keyboards and mice at login"

systemctl --user daemon-reload >/dev/null 2>&1 || true

# Report what systemctl actually said; "could not enable" on its own gives
# nothing to act on.
if ! error=$(systemctl --user enable --now omarchy-bluetooth-reconnect.service 2>&1); then
  echo "Could not enable omarchy-bluetooth-reconnect.service: $error"
fi
