# Fix disable-while-typing on ASUS ROG Flow Z13 detachable keyboard.
#
# The Z13's detachable keyboard touchpad is detected as external by udev,
# which prevents libinput's disable-while-typing (dwt) from pairing it
# with the keyboard. This causes ghost touchpad taps from keyboard
# flex/vibration while typing quickly, jumping the cursor to random positions.
#
# Upstream libinput (50-system-asus.quirks) marks the keyboard as internal
# (AttrKeyboardIntegration=internal), but touchpad integration is controlled
# via udev, not libinput quirks. This udev rule marks the touchpad as internal
# so dwt can properly pair it with the keyboard.

z13_present() {
  [[ $(cat /sys/class/dmi/id/product_name 2>/dev/null) == *GZ302* ]]
}

if omarchy-hw-asus-rog && z13_present; then
  sudo tee /etc/udev/rules.d/99-omarchy-asus-z13-touchpad.rules > /dev/null <<'EOF'
ACTION=="add|change", KERNEL=="event*", ATTRS{idVendor}=="0b05", ATTRS{idProduct}=="1a30", ENV{ID_INPUT_TOUCHPAD}=="1", ENV{ID_INPUT_TOUCHPAD_INTEGRATION}="internal"
EOF
  sudo udevadm control --reload-rules
fi
