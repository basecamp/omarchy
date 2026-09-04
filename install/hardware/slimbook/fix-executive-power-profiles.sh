# Let power profile changes reach the fan and TDP modes on Slimbook laptops.
#
# The Executive and its qc71 siblings register no ACPI platform_profile, so
# power-profiles-daemon falls back to its placeholder platform driver and only
# moves intel_pstate's energy_performance_preference. The fan and TDP modes sit
# behind a root-owned attribute of the qc71 platform driver, out of reach of the
# desktop. This hands that attribute to the wheel group so
# omarchy-powerprofiles-sync-hardware can apply the profile the user picked.
#
# Gated on the vendor, not the driver: Slimbook ships the driver from its own
# repository, so a fresh install usually gets it later. The rule waits for that
# module to bind and hands the attribute over then.

if omarchy-hw-slimbook; then
  sudo mkdir -p /etc/udev/rules.d
  sudo cp -f "$OMARCHY_PATH/default/udev/slimbook-qc71-performance-mode.rules" \
    /etc/udev/rules.d/99-omarchy-slimbook-qc71-performance-mode.rules
  sudo udevadm control --reload

  # Apply to a driver that is already bound, rather than waiting for a reboot.
  # --settle: a plain trigger only queues the event, so the chgrp and chmod it
  # runs are still pending when it returns. Scoped to the platform device: a
  # bare trigger on it also reaches the qc71 input device underneath, and
  # slimbook-service reads any non-add action there as the driver going away,
  # which silently stops it mirroring the profile onto the fan and TDP modes,
  # and every qc71 hotkey with it, for the rest of the session.
  if omarchy-hw-slimbook-qc71; then
    sudo udevadm trigger --settle --action=change --subsystem-match=platform \
      /sys/devices/platform/qc71_laptop
  fi
fi
