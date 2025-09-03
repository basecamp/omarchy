echo "Enable UFW systemd service for existing installations"

# Check if UFW is installed and configured but systemd service not enabled
if command -v ufw >/dev/null 2>&1; then
  # Check if UFW has rules configured (indicating it was set up by Omarchy)
  if sudo ufw status | grep -q "Status: active\|22/tcp\|53317"; then
    # Enable UFW systemd service if not already enabled
    if ! systemctl is-enabled ufw >/dev/null 2>&1; then
      sudo systemctl enable ufw
      echo "UFW systemd service enabled"
    fi
  fi
fi