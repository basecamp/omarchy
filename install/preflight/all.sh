source $OMARCHY_INSTALL/preflight/guard.sh
source $OMARCHY_INSTALL/preflight/begin.sh
run_logged $OMARCHY_INSTALL/preflight/show-env.sh

# online-git is the only mode that bootstraps pacman config; iso-chroot has
# archinstall do it; online-package starts with pacman already configured.
if install_mode_is online-git; then
  run_logged $OMARCHY_INSTALL/preflight/pacman.sh
fi

run_logged $OMARCHY_INSTALL/preflight/migrations.sh

# first-run-mode and disable-mkinitcpio are only meaningful when we're
# bringing a system up from scratch (boot.sh or ISO). online-package mode
# is bolting Omarchy onto an existing Arch install — neither applies.
if ! install_mode_is online-package; then
  run_logged $OMARCHY_INSTALL/preflight/first-run-mode.sh
  run_logged $OMARCHY_INSTALL/preflight/disable-mkinitcpio.sh
fi
