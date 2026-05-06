echo "Fix display backlight on supported ASUS Panther Lake laptops"

EXPERTBOOK_DROP_IN="/etc/limine-entry-tool.d/asus-expertbook-b9406-display.conf"

if omarchy-hw-asus-expertbook-b9406 || omarchy-hw-asus-zenbook-ux5406aa; then
  if [[ -f $EXPERTBOOK_DROP_IN ]]; then
    sudo sed -i '/xe\.enable_dpcd_backlight/d' "$EXPERTBOOK_DROP_IN"
  fi

  source "$OMARCHY_PATH/install/config/hardware/asus/fix-asus-ptl-display-backlight.sh"

  sudo limine-update
fi
