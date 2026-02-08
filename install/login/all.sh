run_logged $OMARCHY_INSTALL/login/plymouth.sh
run_logged $OMARCHY_INSTALL/login/default-keyring.sh
# run_logged $OMARCHY_INSTALL/login/sddm.sh  # using greetd instead
run_logged $OMARCHY_INSTALL/login/greetd.sh
# run_logged $OMARCHY_INSTALL/login/limine-snapper.sh  # CachyOS handles bootloader
