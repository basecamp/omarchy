source $OMARCHY_INSTALL/preflight/guard.sh
source $OMARCHY_INSTALL/preflight/begin.sh
run_logged $OMARCHY_INSTALL/preflight/show-env.sh
run_logged $OMARCHY_INSTALL/preflight/migrations.sh

# Offline (ISO chroot) bootstraps a system from scratch and needs the
# first-run-mode sudoers shim plus the temporary mkinitcpio hook freeze.
# Online installs run on an existing system that already has its own users.
if install_mode_is offline; then
  run_logged $OMARCHY_INSTALL/preflight/first-run-mode.sh
  run_logged $OMARCHY_INSTALL/preflight/disable-mkinitcpio.sh
fi
