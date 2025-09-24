#!/bin/bash

sudo mkdir -p /etc/systemd/system-sleep

sudo tee /etc/systemd/system-sleep/omarchy-network-resume >/dev/null <<'EOF'
#!/bin/bash
set -euo pipefail

restart_service_if_present() {
  local service="$1"

  if ! systemctl list-unit-files "$service" >/dev/null 2>&1; then
    return
  fi

  if systemctl --quiet is-enabled "$service" 2>/dev/null || \
     systemctl --quiet is-active "$service" 2>/dev/null; then
    systemctl restart "$service"
  fi
}

case "${1:-}" in
  post)
    logger -t omarchy-network-resume "Refreshing network stack after resume"
    restart_service_if_present systemd-networkd.service
    restart_service_if_present iwd.service
    ;;
  *)
    ;;
esac
EOF

sudo chmod +x /etc/systemd/system-sleep/omarchy-network-resume
