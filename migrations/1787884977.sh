echo "Set Tailscale operator so Taildrop receive can read files"

if omarchy-cmd-present tailscale; then
  # One machine-wide operator. Do not steal it from another user, and do not
  # mark this complete if sudo is cancelled or tailscaled is down.
  if ! prefs=$(sudo tailscale debug prefs 2>&1); then
    echo "Could not read Tailscale preferences: $prefs"
    echo "The Tailscale operator repair will be retried by omarchy-migrate."
    exit 1
  fi

  operator=$(printf '%s\n' "$prefs" | awk -F'"' '/"OperatorUser"/ { print $4; exit }')

  if [[ -n $operator && $operator != "$USER" ]]; then
    echo "Tailscale operator is already $operator; leaving it unchanged."
    # 1785101000 may already have started this user's receiver. It cannot
    # receive files without being the operator, so stop the access-denied loop.
    systemctl --user disable --now omarchy-tailscale-receive.service 2>/dev/null || true
  else
    if [[ $operator != "$USER" ]]; then
      if ! error=$(sudo tailscale set --operator="$USER" 2>&1); then
        echo "Could not set Tailscale operator: $error"
        echo "The Tailscale operator repair will be retried by omarchy-migrate."
        exit 1
      fi
    fi

    systemctl --user daemon-reload >/dev/null 2>&1 || true

    if ! error=$(systemctl --user enable --now omarchy-tailscale-receive.service 2>&1); then
      echo "Could not enable omarchy-tailscale-receive.service: $error"
      echo "The Tailscale operator repair will be retried by omarchy-migrate."
      exit 1
    fi
  fi
fi
