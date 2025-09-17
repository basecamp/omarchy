echo "Enable UFW systemd service for existing installations"

if omarchy-cmd-present ufw; then
    if sudo ufw status | grep -q "Status: active\|22/tcp\|53317"; then
        if ! systemctl is-enabled ufw >/dev/null 2>&1; then
            sudo systemctl enable ufw --now
            echo "UFW systemd service enabled"
        fi
    fi
fi

