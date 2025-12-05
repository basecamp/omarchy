# Clean filtered files for fresh install run in case of cancel/retry.
rm -f "$OMARCHY_INSTALL/user-selected-aur.packages"
rm -f "$OMARCHY_INSTALL/user-selected.packages"

source $OMARCHY_INSTALL/packaging/select-install.sh omarch-me-sys-extra.packages 'extra system'
source $OMARCHY_INSTALL/packaging/select-install.sh omarch-me-media.packages 'media/communications'
source $OMARCHY_INSTALL/packaging/select-install.sh omarch-me-dev.packages 'developer'
source $OMARCHY_INSTALL/packaging/select-install.sh omarch-me-unfree.packages 'unfree (proprietary)'

