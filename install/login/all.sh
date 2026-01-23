run_logged $OMARCHY_INSTALL/login/plymouth.sh
run_logged $OMARCHY_INSTALL/login/default-keyring.sh

# ARM uses greetd (Wayland-native, works on Pi/SBCs without X)
# x86 uses SDDM (familiar visual greeter)
if [[ -n "$OMARCHY_ARM" ]]; then
  run_logged $OMARCHY_INSTALL/login/greetd.sh
else
  run_logged $OMARCHY_INSTALL/login/sddm.sh
fi

run_logged $OMARCHY_INSTALL/login/limine-snapper.sh
run_logged $OMARCHY_INSTALL/login/limine-arm64.sh
