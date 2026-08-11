echo "Enable working display backlight on supported Dell XPS OLED laptops"

if omarchy-hw-dell-xps-oled; then
  source "$OMARCHY_PATH/install/config/hardware/dell/fix-dell-xps-oled-backlight.sh"

  if omarchy-cmd-present limine-update; then
    sudo limine-update
  fi
fi
