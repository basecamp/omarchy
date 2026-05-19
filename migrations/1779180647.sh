echo "Remove the omarchy-shell user service and old standalone Quickshells"

systemctl --user disable --now omarchy-shell.service >/dev/null 2>&1 || true
rm -f ~/.config/systemd/user/omarchy-shell.service
systemctl --user daemon-reload >/dev/null 2>&1 || true

for pid in $(pgrep -f "quickshell .* -p $OMARCHY_PATH/default/quickshell/(menu|select-by-image)\.qml" || true); do
  kill "$pid" 2>/dev/null || true
done

omarchy-restart-shell
