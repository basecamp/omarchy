run_logged $OMARCHY_INSTALL/login/sddm.sh
if install_mode_is online; then
  run_logged $OMARCHY_INSTALL/login/hibernation.sh
fi
run_logged $OMARCHY_INSTALL/login/limine-snapper.sh
