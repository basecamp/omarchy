
if omarchy-hibernation-available; then
  echo "Swap already created, skipping migration";
  exit 0;
fi

MEM_TOTAL_HUMAN="$(free --human |grep "Mem" |awk '{print $2}')"
if gum confirm "Use $MEM_TOTAL_HUMAN on drive to create swap and make hibernation available?"; then
  source  $OMARCHY_PATH/install/config/hibernation.sh
fi
