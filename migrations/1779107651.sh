echo "Move omarchy-shell to the top-level shell directory"

mkdir -p ~/.config/systemd/user
cp "$OMARCHY_PATH/config/systemd/user/omarchy-shell.service" ~/.config/systemd/user/omarchy-shell.service
systemctl --user daemon-reload

if omarchy-cmd-present quickshell; then
  quickshell kill -p "$OMARCHY_PATH/default/quickshell"/omarchy-shell >/dev/null 2>&1 || true
fi

if systemctl --user is-enabled --quiet omarchy-shell.service || systemctl --user is-active --quiet omarchy-shell.service; then
  systemctl --user restart omarchy-shell.service || true
fi
