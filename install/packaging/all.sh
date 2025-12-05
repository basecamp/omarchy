# Need to pause log for TUIs to display properly.
pause_log
if gum confirm 'Install all default Omarchy apps?' --negative 'Customise'; then
  unpause_log 'Installing all default Omarchy packages...'
  run_logged $OMARCHY_INSTALL/packaging/base.sh
else
  unpause_log 'Installing only basic system packages (open source)...'
  run_logged $OMARCHY_INSTALL/packaging/omarch-me-system.sh
  
  pause_log
  source $OMARCHY_INSTALL/packaging/custom.sh
  unpause_log 'Installing user-selected applications...'
  
  run_logged $OMARCHY_INSTALL/packaging/omarch-me-user-selected.sh
fi

run_logged $OMARCHY_INSTALL/packaging/fonts.sh
run_logged $OMARCHY_INSTALL/packaging/nvim.sh
run_logged $OMARCHY_INSTALL/packaging/icons.sh

pause_log
if gum confirm 'Install all default Omarchy webapps? (Can be easily added/removed later in Omarchy menu)'; then
  unpause_log 'Installing webapps, TUIs and configs'
  run_logged $OMARCHY_INSTALL/packaging/webapps.sh
else
  unpause_log 'Installing TUIs and configs'
fi
run_logged $OMARCHY_INSTALL/packaging/tuis.sh
