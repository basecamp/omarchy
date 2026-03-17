echo "Install delayed-hibernate hook for automatic hibernate after 90min suspend"

# Only apply if hibernation is already set up
if [[ -f /etc/mkinitcpio.conf.d/omarchy_resume.conf ]]; then
  sudo mkdir -p /usr/lib/systemd/system-sleep
  sudo install -m 0755 -o root -g root "$OMARCHY_PATH/default/systemd/system-sleep/delayed-hibernate" /usr/lib/systemd/system-sleep/

  # Remove old suspend-then-hibernate config and service if present
  sudo rm -f /etc/systemd/logind.conf.d/lid.conf /etc/systemd/sleep.conf.d/hibernate.conf
  sudo systemctl disable delayed-hibernate.service 2>/dev/null
  sudo rm -f /etc/systemd/system/delayed-hibernate.service
fi
