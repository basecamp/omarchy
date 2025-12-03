gum confirm 'Install all default Omarchy apps?' --negative 'Customise' && run_logged $OMARCHY_INSTALL/packaging/base.sh || source $OMARCHY_INSTALL/packaging/custom.sh
run_logged $OMARCHY_INSTALL/packaging/fonts.sh
run_logged $OMARCHY_INSTALL/packaging/nvim.sh
run_logged $OMARCHY_INSTALL/packaging/icons.sh
gum confirm 'Install all default Omarchy webapps? (Can be easily added/removed later in Omarchy menu)' && run_logged $OMARCHY_INSTALL/packaging/webapps.sh
run_logged $OMARCHY_INSTALL/packaging/tuis.sh
