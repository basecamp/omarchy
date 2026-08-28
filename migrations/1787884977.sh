echo "Set Tailscale operator so Taildrop receive can read files"

if omarchy-cmd-present tailscale; then
  # The receiver runs as the user; without --operator it only loops
  # "Access denied" every ten seconds. Match the installer.
  if ! error=$(sudo tailscale set --operator="$USER" 2>&1); then
    echo "Could not set Tailscale operator: $error"
  else
    systemctl --user daemon-reload >/dev/null 2>&1 || true

    if ! error=$(systemctl --user enable --now omarchy-tailscale-receive.service 2>&1); then
      echo "Could not enable omarchy-tailscale-receive.service: $error"
    fi
  fi
fi
