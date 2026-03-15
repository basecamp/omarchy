# Install Tuxedo drivers for keyboard backlighting on Tuxedo laptops and
# compatible devices like the Slimbook Executive (Clevo/Tuxedo chassis).
if cat /sys/class/dmi/id/sys_vendor 2>/dev/null | grep -qi "TUXEDO\|Slimbook"; then
  omarchy-pkg-add linux-headers tuxedo-drivers-nocompatcheck-dkms

  # Blacklist the legacy clevo_xsm_wmi module which conflicts with the tuxedo-drivers
  # clevo_wmi module. When clevo_xsm_wmi loads first, it grabs the Clevo WMI GUIDs,
  # preventing tuxedo-drivers from initializing the keyboard backlight properly.
  echo "blacklist clevo_xsm_wmi" | sudo tee /etc/modprobe.d/blacklist-clevo-xsm-wmi.conf > /dev/null

  # Remove any orphaned clevo_xsm_wmi module files not managed by a package
  for f in /lib/modules/*/extra/clevo-xsm-wmi.ko; do
    [ -f "$f" ] && sudo rm "$f"
  done
fi
