echo "Switching system authentication prompt to dark mode"
if [[ ! -f ~/.config/systemd/user/hyprpolkitagent.service.d/override.conf ]]; then
  source ~/.local/share/omarchy/install/hyprpolkitagent.sh

  # Reload user systemd and restart service
  systemctl --user daemon-reexec
  systemctl --user daemon-reload
  systemctl --user restart hyprpolkitagent
fi
