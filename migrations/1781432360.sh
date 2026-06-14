echo "Fix touchpad quirk on ASUS ExpertBook B9406 (was written to a path libinput never reads)"

if omarchy-hw-asus-expertbook-b9406; then
  source "$OMARCHY_PATH/install/config/hardware/asus/fix-asus-ptl-b9406-touchpad.sh"
fi
