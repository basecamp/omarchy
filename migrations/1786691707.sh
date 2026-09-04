echo "Remove legacy power profile udev rules superseded by Quattro"

rules_dir="${OMARCHY_POWERPROFILES_UDEV_RULES_DIR:-/etc/udev/rules.d}"
legacy_rule="$rules_dir/99-power-profile.rules"
retired_package_rule="$rules_dir/99-omarchy-power-profile.rules"

# Quattro restores per-source preferences through the shell's UPower service.
# Rules left by older releases run the same helper through the system manager,
# where it cannot see the user's saved preference and falls back to performance.
if [[ -e $legacy_rule || -L $legacy_rule || -e $retired_package_rule || -L $retired_package_rule ]]; then
  sudo rm -f "$legacy_rule" "$retired_package_rule"
  sudo udevadm control --reload 2>/dev/null
fi
