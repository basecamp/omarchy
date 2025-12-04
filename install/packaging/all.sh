stop_log_output
if gum confirm 'Install all default Omarchy apps?' --negative 'Customise'; then
  start_log_output
  run_logged $OMARCHY_INSTALL/packaging/base.sh
else
  start_log_output
  run_logged $OMARCHY_INSTALL/packaging/custom.sh
fi

run_logged $OMARCHY_INSTALL/packaging/fonts.sh
run_logged $OMARCHY_INSTALL/packaging/nvim.sh
run_logged $OMARCHY_INSTALL/packaging/icons.sh

stop_log_output
if gum confirm 'Install all default Omarchy webapps? (Can be easily added/removed later in Omarchy menu)'; then
  start_log_output
  run_logged $OMARCHY_INSTALL/packaging/webapps.sh
else
  start_log_output
fi
run_logged $OMARCHY_INSTALL/packaging/tuis.sh
