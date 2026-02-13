run_logged $OMARCHY_INSTALL/packaging/base.sh
run_logged $OMARCHY_INSTALL/packaging/fonts.sh
run_logged $OMARCHY_INSTALL/packaging/nvim.sh
run_logged $OMARCHY_INSTALL/packaging/icons.sh
run_logged $OMARCHY_INSTALL/packaging/webapps.sh
run_logged $OMARCHY_INSTALL/packaging/tuis.sh
run_logged $OMARCHY_INSTALL/packaging/eww.sh
if [[ "${OMARCHY_BLACKARCH:-0}" == "1" ]]; then
  run_logged $OMARCHY_INSTALL/packaging/blackarch-repo.sh
  run_logged $OMARCHY_INSTALL/packaging/blackarch-essentials.sh
fi
run_logged $OMARCHY_INSTALL/packaging/asus-rog.sh
