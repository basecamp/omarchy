echo "Add Requires=power-profiles-daemon.service to power profile udev rule"

RULES_FILE="/etc/udev/rules.d/99-power-profile.rules"
if [[ -f $RULES_FILE ]]; then
  sudo sed -i 's/--property=After=power-profiles-daemon.service/--property=Requires=power-profiles-daemon.service --property=After=power-profiles-daemon.service/g' "$RULES_FILE"
  sudo udevadm control --reload 2>/dev/null
fi
