run_logged $OMARCHY_INSTALL/post-install/first-run-mode.sh
run_logged $OMARCHY_INSTALL/post-install/pacman.sh
run_logged $OMARCHY_INSTALL/post-install/legacy-cleanup.sh
run_logged $OMARCHY_INSTALL/post-install/udev.sh
run_logged $OMARCHY_INSTALL/post-install/localdb.sh
if install_mode_is online; then
  run_logged $OMARCHY_INSTALL/post-install/allow-reboot.sh
fi
