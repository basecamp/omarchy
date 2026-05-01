echo "Refresh Dell XPS haptic touchpad service for configurable intensity"

if omarchy-hw-dell-xps-haptic-touchpad; then
  source "$OMARCHY_PATH/install/config/hardware/dell/fix-xps-haptic-touchpad.sh"
  omarchy-update-dell-haptic
fi
