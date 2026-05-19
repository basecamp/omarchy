echo "Remove the omarchy-shell user service"

systemctl --user disable --now omarchy-shell.service >/dev/null 2>&1 || true
rm -f ~/.config/systemd/user/omarchy-shell.service
systemctl --user daemon-reload >/dev/null 2>&1 || true

omarchy-restart-shell
