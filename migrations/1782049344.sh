echo "Disable Limine Snapper warning notifier"

autostart_file="$HOME/.config/autostart/limine-snapper-notify.desktop"

mkdir -p "$(dirname "$autostart_file")"
cat >"$autostart_file" <<'DESKTOP'
[Desktop Entry]
Hidden=true
DESKTOP

systemctl --user stop 'app-limine\x2dsnapper\x2dnotify@autostart.service' >/dev/null 2>&1 || true
systemctl --user daemon-reload >/dev/null 2>&1 || true
