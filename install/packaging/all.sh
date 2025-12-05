pause_log
if gum confirm 'Install all default Omarchy apps?' --negative 'Customise'; then
  unpause_log 'Installing all default Omarchy packages...'
  run_logged $OMARCHY_INSTALL/packaging/base.sh
else
  unpause_log 'Installing only basic system packages (open source)...'
  run_logged $OMARCHY_INSTALL/packaging/custom.sh
fi

run_logged $OMARCHY_INSTALL/packaging/fonts.sh
run_logged $OMARCHY_INSTALL/packaging/nvim.sh
run_logged $OMARCHY_INSTALL/packaging/icons.sh

pause_log
if gum confirm 'Install all default Omarchy webapps? (Can be easily added/removed later in Omarchy menu)'; then
  unpause_log
  run_logged $OMARCHY_INSTALL/packaging/webapps.sh
else
  unpause_log
fi
run_logged $OMARCHY_INSTALL/packaging/tuis.sh
