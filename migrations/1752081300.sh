echo "Switching system authentication prompt to dark mode"
source ~/.local/share/omarchy/install/hyprpolkitagent.sh

# Reload user systemd and restart service
systemctl --user daemon-reexec
systemctl --user daemon-reload
systemctl --user restart hyprpolkitagent
