echo "Fix hybrid GPU sleep hook and disable nvidia sleep services in integrated mode"

# Only applies to systems with supergfxctl configured
if omarchy-cmd-present supergfxctl && [[ -f /etc/supergfxd.conf ]]; then
  current_mode=$(awk -F'"' '/"mode"/ { print $(NF-1) }' /etc/supergfxd.conf 2>/dev/null | head -n1)

  # Fix execute bit on force-igpu sleep hook
  if [[ -f /usr/lib/systemd/system-sleep/force-igpu ]]; then
    sudo chmod +x /usr/lib/systemd/system-sleep/force-igpu
  fi

  if [[ $current_mode == "Integrated" ]]; then
    # Disable nvidia sleep/resume services
    sudo systemctl disable nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service 2>/dev/null
  fi
fi
