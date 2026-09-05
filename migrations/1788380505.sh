echo "Relay SSH agent requests in Herdr panes to the forwarded or local agent"

systemctl --user daemon-reload >/dev/null 2>&1 || true

# Report what systemctl actually said; "could not enable" on its own gives
# nothing to act on.
if ! error=$(systemctl --user enable --now omarchy-ssh-agent-proxy.socket 2>&1); then
  echo "Could not enable omarchy-ssh-agent-proxy.socket: $error"
fi
