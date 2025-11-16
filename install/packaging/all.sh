# Skip base package installation if running from archinstall wrapper
# The wrapper already installed base packages before user creation
if [[ -z "$OMARCHY_ARCHINSTALL_WRAPPER" ]]; then
    run_logged $OMARCHY_INSTALL/packaging/base.sh
fi

run_logged $OMARCHY_INSTALL/packaging/apps.sh
run_logged $OMARCHY_INSTALL/packaging/fonts.sh
run_logged $OMARCHY_INSTALL/packaging/nvim.sh
run_logged $OMARCHY_INSTALL/packaging/webapps.sh
run_logged $OMARCHY_INSTALL/packaging/tuis.sh
