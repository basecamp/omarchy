run_logged "$OMARCHY_INSTALL/config/theme-system.sh"
run_logged "$OMARCHY_INSTALL/config/browser-policy.sh"
run_logged "$OMARCHY_INSTALL/config/increase-lockout-limit.sh"
run_logged "$OMARCHY_INSTALL/config/lockscreen-pam.sh"
run_logged "$OMARCHY_INSTALL/config/fix-powerprofilesctl-shebang.sh"
run_logged "$OMARCHY_INSTALL/config/ssh-command-path.sh"
run_logged "$OMARCHY_INSTALL/config/ssh-keepalive.sh"
run_logged "$OMARCHY_INSTALL/config/docker.sh"
# Apple Silicon boots through m1n1 + GRUB from the Asahi packages, not Limine,
# so the snapshot boot entries snapper is wired to here do not exist there and
# the config would only ever produce snapshots nothing can boot.
if ! omarchy-hw-apple-silicon; then
  run_logged "$OMARCHY_INSTALL/config/snapper.sh"
fi
run_logged "$OMARCHY_INSTALL/config/locate.sh"
run_logged "$OMARCHY_INSTALL/config/enable-services.sh"
run_logged "$OMARCHY_INSTALL/config/firewall.sh"
