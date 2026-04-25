echo "Fix disable-while-typing on ASUS ROG Flow Z13 detachable keyboard"

if omarchy-hw-asus-rog && lsusb | grep -q "0b05:1a30"; then
  sudo tee /etc/udev/rules.d/99-omarchy-asus-z13-touchpad.rules > /dev/null <<'EOF'
ACTION=="add|change", KERNEL=="event*", ATTRS{idVendor}=="0b05", ATTRS{idProduct}=="1a30", ENV{ID_INPUT_TOUCHPAD}=="1", ENV{ID_INPUT_TOUCHPAD_INTEGRATION}="internal"
EOF
  sudo udevadm control --reload-rules
  omarchy-state set reboot-required
fi
