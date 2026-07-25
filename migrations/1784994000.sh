echo "Save incoming Taildrop files to ~/Downloads"

if omarchy-cmd-present tailscale; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user enable --now omarchy-tailscale-receive.service >/dev/null 2>&1 ||
    echo "Could not enable omarchy-tailscale-receive.service"
fi
