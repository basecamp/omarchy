run_logged "$OMARCHY_INSTALL/user/theme.sh"
run_logged "$OMARCHY_INSTALL/user/chromium.sh"
run_logged "$OMARCHY_INSTALL/user/git.sh"
run_logged "$OMARCHY_INSTALL/user/xcompose.sh"
run_logged "$OMARCHY_INSTALL/user/mise-work.sh"

run_logged "$OMARCHY_INSTALL/user/hardware/asus/fix-audio-mixer.sh"
run_logged "$OMARCHY_INSTALL/user/hardware/asus/fix-mic.sh"
run_logged "$OMARCHY_INSTALL/user/hardware/framework/fix-f13-amd-audio-input.sh"
run_logged "$OMARCHY_INSTALL/user/hardware/dell/xps13-text-scaling.sh"
run_logged "$OMARCHY_INSTALL/user/hardware/fix-nouveau-cursor.sh"

run_logged "$OMARCHY_INSTALL/user/default-keyring.sh"
run_logged "$OMARCHY_INSTALL/user/mise.sh"

# Last: the theme must already be set for the background thumbnails to build.
run_logged "$OMARCHY_INSTALL/user/warm-caches.sh"
