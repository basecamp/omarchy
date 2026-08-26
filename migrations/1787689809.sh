echo "Prevent Dell Latitude 7490 i915 hibernation resume hangs"

source "$OMARCHY_PATH/install/hardware/intel/fix-dell-latitude-7490-hibernate.sh"

if (( OMARCHY_LATITUDE_7490_CHANGED )); then
  omarchy-state set reboot-required
fi
