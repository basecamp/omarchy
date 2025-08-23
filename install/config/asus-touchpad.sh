#!/bin/bash

# Fix touchpad detection on ASUS Flow Z13
if grep -qi "flow z13" /sys/class/dmi/id/product_name 2>/dev/null; then
  if [[ ! -f /etc/modprobe.d/hid_asus.conf ]]; then
    echo "options hid_asus enable_touchpad=1" | sudo tee /etc/modprobe.d/hid_asus.conf >/dev/null
    
    # Create systemd service to reload hid_asus module on boot
    sudo tee /etc/systemd/system/reload-hid_asus.service >/dev/null <<'EOF'
[Unit]
Description=Reload hid_asus with correct options
After=multi-user.target
ConditionKernelModule=hid_asus

[Service]
Type=oneshot
ExecStart=/usr/bin/modprobe -r hid_asus
ExecStart=/usr/bin/modprobe hid_asus

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl enable reload-hid_asus.service
  fi
fi