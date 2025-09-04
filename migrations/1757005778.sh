#!/bin/bash

echo "Fix NetworkManager DNS conflicts with systemd-resolved"

# Check if NetworkManager is installed and running
if ! command -v nmcli >/dev/null 2>&1; then
    echo "NetworkManager not found, skipping DNS configuration fix"
    exit 0
fi

if ! systemctl is-active --quiet NetworkManager; then
    echo "NetworkManager not running, skipping DNS configuration fix"
    exit 0
fi

# Check if systemd-resolved is available
if ! systemctl is-active --quiet systemd-resolved; then
    echo "systemd-resolved not running, skipping DNS configuration fix"
    exit 0
fi

echo "NetworkManager detected, checking for DNS configuration conflicts..."

# Check if NetworkManager is already configured to work with systemd-resolved properly
NM_DNS_CONFIG="/etc/NetworkManager/conf.d/99-dns-systemd-resolved.conf"
NEEDS_CONFIG_FIX=false
NEEDS_CONNECTION_FIX=false

# Check if NetworkManager DNS configuration exists and is correct
if [[ ! -f "$NM_DNS_CONFIG" ]]; then
    NEEDS_CONFIG_FIX=true
    echo "  - Missing NetworkManager DNS configuration"
elif ! grep -q "dns=systemd-resolved" "$NM_DNS_CONFIG" 2>/dev/null; then
    NEEDS_CONFIG_FIX=true
    echo "  - Incorrect NetworkManager DNS configuration"
fi

# Check for connections with hardcoded DNS that conflict with systemd-resolved
if nmcli -t connection show | while IFS=: read name uuid type device; do
    if [[ -n "$device" && "$device" != "--" ]]; then
        # Check if this connection has DNS configured
        DNS_SERVERS=$(nmcli -t -f ipv4.dns connection show "$name" 2>/dev/null | cut -d: -f2)
        if [[ -n "$DNS_SERVERS" && "$DNS_SERVERS" != "" ]]; then
            echo "  - Connection '$name' has hardcoded DNS: $DNS_SERVERS"
            exit 1  # Signal that we found a connection needing fix
        fi
    fi
done; then
    # No connections with hardcoded DNS found
    true
else
    NEEDS_CONNECTION_FIX=true
fi

# Apply fixes if needed
if [[ "$NEEDS_CONFIG_FIX" == "true" ]]; then
    echo "Configuring NetworkManager to work properly with systemd-resolved..."
    sudo tee "$NM_DNS_CONFIG" >/dev/null <<'EOF'
[main]
dns=systemd-resolved
systemd-resolved=false

[global-dns-domain-*]
servers=none
EOF
    echo "  - Created NetworkManager DNS configuration"
fi

if [[ "$NEEDS_CONNECTION_FIX" == "true" ]]; then
    echo "Removing hardcoded DNS from NetworkManager connections..."
    # Fix all connections that have hardcoded DNS
    nmcli -t connection show | while IFS=: read name uuid type device; do
        if [[ -n "$device" && "$device" != "--" ]]; then
            DNS_SERVERS=$(nmcli -t -f ipv4.dns connection show "$name" 2>/dev/null | cut -d: -f2)
            if [[ -n "$DNS_SERVERS" && "$DNS_SERVERS" != "" ]]; then
                echo "  - Clearing DNS from connection '$name'"
                sudo nmcli connection modify "$name" ipv4.dns "" 2>/dev/null || true
            fi
        fi
    done
fi

# Restart NetworkManager if we made changes
if [[ "$NEEDS_CONFIG_FIX" == "true" || "$NEEDS_CONNECTION_FIX" == "true" ]]; then
    echo "Restarting NetworkManager to apply changes..."
    sudo systemctl restart NetworkManager
    sleep 2  # Give NetworkManager time to restart
    echo "NetworkManager DNS configuration fixed!"
else
    echo "NetworkManager DNS configuration is already correct"
fi
