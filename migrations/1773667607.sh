echo "Install delayed-hibernate hook for automatic hibernate after 90min suspend"

# Only apply if hibernation is already set up
if [[ -f /etc/mkinitcpio.conf.d/omarchy_resume.conf ]]; then
  sudo mkdir -p /usr/lib/systemd/system-sleep
  sudo install -m 0755 -o root -g root "$OMARCHY_PATH/default/systemd/system-sleep/delayed-hibernate" /usr/lib/systemd/system-sleep/
  sudo cp "$OMARCHY_PATH/default/systemd/delayed-hibernate.service" /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable delayed-hibernate.service

  # Remove old suspend-then-hibernate config if present
  sudo rm -f /etc/systemd/logind.conf.d/lid.conf /etc/systemd/sleep.conf.d/hibernate.conf
fi
