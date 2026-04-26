echo "Fix disable-while-typing on ASUS ROG Flow Z13 detachable keyboard"

source $OMARCHY_PATH/install/config/hardware/asus/fix-z13-touchpad.sh

if [[ -f /etc/udev/rules.d/99-omarchy-asus-z13-touchpad.rules ]]; then
  omarchy-state set reboot-required
fi
