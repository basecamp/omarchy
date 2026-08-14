echo "Remove legacy power profile udev rules superseded by Quattro"

rules_dir="${OMARCHY_POWERPROFILES_UDEV_RULES_DIR:-/etc/udev/rules.d}"

# Quattro restores per-source preferences through the shell's UPower service.
# Rules left by older releases run the same helper through the system manager,
# where it cannot see the user's saved preference and falls back to performance.
sudo rm -f \
  "$rules_dir/99-power-profile.rules" \
  "$rules_dir/99-omarchy-power-profile.rules"

sudo udevadm control --reload 2>/dev/null
