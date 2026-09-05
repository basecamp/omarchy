echo "Install the battery charge-limit sudoers rule and boot-restore service"

# The one-click charge-limit picker elevates omarchy-battery-limit-set through
# the passwordless grant in etc/sudoers.d/omarchy-battery-limit. The package
# owns that file for fresh installs; existing installs pick it up here.
sudo install -D -m 440 "$OMARCHY_PATH/etc/sudoers.d/omarchy-battery-limit" /etc/sudoers.d/omarchy-battery-limit

# Only laptops whose battery exposes charge_control_end_threshold get the
# boot-restore unit; everywhere else there is nothing for it to re-apply.
# Idempotent: install over an identical copy and re-enabling an enabled unit
# both no-op.
if omarchy-hw-battery-charge-limit; then
  sudo install -D -m 644 "$OMARCHY_PATH/default/systemd/system/omarchy-battery-limit.service" /etc/systemd/system/omarchy-battery-limit.service
  sudo systemctl daemon-reload
  sudo systemctl enable omarchy-battery-limit.service >/dev/null 2>&1 || true
fi
