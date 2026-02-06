# Allow unprivileged access to the Framework 16 keyboard for RGB control via qmk_hid.

if omarchy-hw-framework16; then
  if [[ ! -f /etc/udev/rules.d/50-framework16-qmk-hid.rules ]]; then
    cat <<EOF | sudo tee /etc/udev/rules.d/50-framework16-qmk-hid.rules
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="32ac", ATTRS{idProduct}=="0012", MODE="0660", TAG+="uaccess"
EOF

    sudo udevadm control --reload-rules
    sudo udevadm trigger
  fi
fi
