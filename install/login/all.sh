# Source bootloader detection
source "$OMARCHY_INSTALL/helpers/bootloader-detect.sh" 2>/dev/null || true

# Handle bootloader based on mode
if declare -f handle_bootloader >/dev/null 2>&1; then
    handle_bootloader
fi

# Continue with existing login components
run_logged $OMARCHY_INSTALL/login/plymouth.sh
run_logged $OMARCHY_INSTALL/login/default-keyring.sh
run_logged $OMARCHY_INSTALL/login/sddm.sh
run_logged $OMARCHY_INSTALL/login/hibernation.sh

# Only run limine-snapper in fresh mode
if [[ "$OMARCHY_INSTALL_MODE" == "fresh" ]]; then
    run_logged $OMARCHY_INSTALL/login/limine-snapper.sh
fi
