stop_log_output
gum confirm 'Install all default Omarchy apps?' --negative 'Customise'; confirmed=$?
start_log_output
if [[ $confirmed == 0 ]]; then
  run_logged $OMARCHY_INSTALL/packaging/base.sh
else
  run_logged $OMARCHY_INSTALL/packaging/custom.sh
fi

run_logged $OMARCHY_INSTALL/packaging/fonts.sh
run_logged $OMARCHY_INSTALL/packaging/nvim.sh
run_logged $OMARCHY_INSTALL/packaging/icons.sh

stop_log_output
gum confirm 'Install all default Omarchy webapps? (Can be easily added/removed later in Omarchy menu)'; confirmed=$?
start_log_output
if [[ $confirmed == 0 ]]; then
  run_logged $OMARCHY_INSTALL/packaging/webapps.sh
fi
run_logged $OMARCHY_INSTALL/packaging/tuis.sh
