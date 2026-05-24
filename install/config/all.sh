run_logged $OMARCHY_INSTALL/config/theme-system.sh
run_logged $OMARCHY_INSTALL/config/increase-lockout-limit.sh
run_logged $OMARCHY_INSTALL/config/lockscreen-pam.sh
run_logged $OMARCHY_INSTALL/config/fix-powerprofilesctl-shebang.sh
run_logged $OMARCHY_INSTALL/config/docker.sh
run_logged $OMARCHY_INSTALL/config/input-group.sh

# Service enables centralized; run after all drop-in files are in place.
run_logged $OMARCHY_INSTALL/config/enable-services.sh

run_logged $OMARCHY_INSTALL/config/hardware/network.sh
run_logged $OMARCHY_INSTALL/config/hardware/set-wireless-regdom.sh
run_logged $OMARCHY_INSTALL/config/hardware/fix-fkeys.sh
run_logged $OMARCHY_INSTALL/config/hardware/fix-synaptic-touchpad.sh
run_logged $OMARCHY_INSTALL/config/hardware/bluetooth.sh
run_logged $OMARCHY_INSTALL/config/hardware/nvidia.sh
run_logged $OMARCHY_INSTALL/config/hardware/vulkan.sh

run_logged $OMARCHY_INSTALL/config/hardware/intel/video-acceleration.sh
run_logged $OMARCHY_INSTALL/config/hardware/intel/lpmd.sh
run_logged $OMARCHY_INSTALL/config/hardware/intel/thermald.sh
run_logged $OMARCHY_INSTALL/config/hardware/intel/ipu7-camera.sh
run_logged $OMARCHY_INSTALL/config/hardware/intel/ptl-kernel.sh
run_logged $OMARCHY_INSTALL/config/hardware/intel/fred.sh
run_logged $OMARCHY_INSTALL/config/hardware/intel/fix-wifi7-eht.sh
run_logged $OMARCHY_INSTALL/config/hardware/intel/sof-firmware.sh

run_logged $OMARCHY_INSTALL/config/hardware/asus/fix-asus-ptl-display-backlight.sh
run_logged $OMARCHY_INSTALL/config/hardware/asus/fix-asus-ptl-b9406-display.sh
run_logged $OMARCHY_INSTALL/config/hardware/asus/fix-asus-ptl-b9406-touchpad.sh
run_logged $OMARCHY_INSTALL/config/hardware/asus/fix-z13-touchpad.sh

run_logged $OMARCHY_INSTALL/config/hardware/framework/qmk-hid.sh

run_logged $OMARCHY_INSTALL/config/hardware/apple/fix-spi-keyboard.sh
run_logged $OMARCHY_INSTALL/config/hardware/apple/fix-suspend-nvme.sh
run_logged $OMARCHY_INSTALL/config/hardware/apple/fix-t2.sh

run_logged $OMARCHY_INSTALL/config/hardware/lenovo/fix-yoga-pro7-bass-speakers.sh

run_logged $OMARCHY_INSTALL/config/hardware/fix-bcm43xx.sh
run_logged $OMARCHY_INSTALL/config/hardware/fix-surface-keyboard.sh
run_logged $OMARCHY_INSTALL/config/hardware/fix-yt6801-ethernet-adapter.sh
run_logged $OMARCHY_INSTALL/config/hardware/fix-tuxedo-backlight.sh
