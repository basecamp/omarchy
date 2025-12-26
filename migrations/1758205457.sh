echo "Offer hibernation if missing as a system-menu option"

if omarchy-hibernation-available; then
  exit 0
fi

MEM_TOTAL_HUMAN="$(free --human |grep "Mem" |awk '{print $2}')"
if gum confirm "Use $MEM_TOTAL_HUMAN on boot drive to make hibernation available?"; then
  source  "$OMARCHY_PATH/install/config/hibernation.sh"
fi
