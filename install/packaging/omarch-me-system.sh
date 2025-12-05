#echo 'Note: certain programs have custom Omarchy configurations which will still be installed even if you don'"'"'t install the program itself.'
#echo 'This is to facilitate program installation at a later date, and the configurations and folders generated can be safely ignored.'
#gum spin --title 'Press any key to continue.' -- bash -c 'read -n 1 -s'
source $OMARCHY_INSTALL/packaging/from-file.sh omarch-me-system.packages
