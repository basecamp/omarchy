#echo 'Note: certain programs have custom Omarchy configurations which will still be installed even if you don'"'"'t install the program itself.'
#echo 'This is to facilitate program installation at a later date, and the configurations and folders generated can be safely ignored.'
#gum spin --title 'Press any key to continue.' -- bash -c 'read -n 1 -s'
source $OMARCHY_INSTALL/packaging/from-file.sh omarch-me-system.packages

pause_log
source $OMARCHY_INSTALL/packaging/select-install.sh omarch-me-sys-extra.packages 'extra system'
source $OMARCHY_INSTALL/packaging/select-install.sh omarch-me-media.packages 'media/communications'
source $OMARCHY_INSTALL/packaging/select-install.sh omarch-me-dev.packages 'developer'
source $OMARCHY_INSTALL/packaging/select-install.sh omarch-me-unfree.packages 'unfree (proprietary)'
unpause_log 'Installing user-selected applications...'
source $OMARCHY_INSTALL/packaging/from-file.sh user-selected.packages
