# System-level install work. Keep the actual logic in the same atomic
# packaging/config/login/post-install scripts used by the online installer.
source $OMARCHY_INSTALL/packaging/system.sh
source $OMARCHY_INSTALL/config/all.sh
source $OMARCHY_INSTALL/login/system.sh
source $OMARCHY_INSTALL/post-install/system.sh
