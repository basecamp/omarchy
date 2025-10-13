echo "Allow updating of timezone by right-clicking on the clock (or running omarchy-cmd-tzupdate)"

if omarchy-cmd-missing tzupdate; then
  bash "$OMARCHY_PATH/install/config/timezones.sh"
  omarchy-refresh-waybar
fi
