# Called by Omarchy ISO setup before starting configurator and archinstall

source "$OMARCHY_INSTALL/preflight/set-size-vars.sh"
source "$OMARCHY_INSTALL/helpers/logo.sh"
source "$OMARCHY_INSTALL/preflight/gum.sh"
source "$OMARCHY_INSTALL/helpers/tail-log-output.sh"
source "$OMARCHY_INSTALL/helpers/trap-errors.sh"

source $OMARCHY_INSTALL/helpers/chroot.sh
source $OMARCHY_INSTALL/helpers/logo.sh
source $OMARCHY_INSTALL/helpers/gum.sh
source $OMARCHY_INSTALL/helpers/errors.sh
source $OMARCHY_INSTALL/helpers/logging.sh
source $OMARCHY_INSTALL/helpers/layout.sh
