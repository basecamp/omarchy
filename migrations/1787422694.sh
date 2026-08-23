echo "Let power profile changes reach the fan and TDP modes on Slimbook laptops"

# install/hardware/slimbook/fix-executive-power-profiles.sh only reaches machines
# set up after it shipped, so an existing Slimbook Executive still keeps the qc71
# performance mode attribute owned by root and out of the desktop's reach. Until
# it is handed over, picking a profile in the bar moves intel_pstate's
# energy_performance_preference and leaves the fan and TDP mode where it was.

# The vendor, not the driver: Slimbook ships the driver from its own repository,
# and a machine that gets it after this runs still needs the rule in place.
omarchy-hw-slimbook || exit 0

rule="${OMARCHY_QC71_UDEV_RULE:-/etc/udev/rules.d/99-omarchy-slimbook-qc71-performance-mode.rules}"
source_rule="$OMARCHY_PATH/default/udev/slimbook-qc71-performance-mode.rules"
performance_mode="${OMARCHY_QC71_PERFORMANCE_MODE:-/sys/devices/platform/qc71_laptop/performance_mode}"

# Machine-wide, so a second user on the same laptop finds it already done.
if [[ ! -f $rule ]] || ! cmp -s "$source_rule" "$rule"; then
  sudo mkdir -p "$(dirname "$rule")"
  sudo cp -f "$source_rule" "$rule"
  sudo udevadm control --reload
fi

# Without the driver bound there is nothing to hand over yet; the rule catches
# the module when it arrives.
omarchy-hw-slimbook-qc71 || exit 0

# Hand the attribute over on the driver that is already bound, rather than
# waiting for a reboot. Keyed on the attribute rather than on the rule file: a
# rule copied by hand but never applied leaves the mode just as unreachable.
# --settle because a plain trigger only queues the event, so its chgrp and chmod
# are still pending when it returns and the sync below would find the attribute
# root-owned and report a failure instead of doing the one job it is here for.
if [[ ! -w $performance_mode ]]; then
  # Scoped to the platform device: a bare trigger on it also reaches the qc71
  # input device underneath, and slimbook-service reads any non-add action there
  # as the driver going away. That silently stops it mirroring the profile onto
  # the fan and TDP modes, and every qc71 hotkey with it, for the rest of the
  # session.
  sudo udevadm trigger --settle --action=change --subsystem-match=platform \
    "$(dirname "$performance_mode")"
fi

# The rule only grants access; the mode itself is still whatever it was left in.
# Hand it the profile that is active right now so the laptop matches the bar
# without waiting for the next profile change.
omarchy-powerprofiles-sync-hardware "$(powerprofilesctl get 2>/dev/null)"
