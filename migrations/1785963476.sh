echo "Enable the D-Bus idle-inhibit daemon so apps can suppress the screensaver"

# Enable + start the idle-inhibit daemon for existing Quattro users. It owns
# org.freedesktop.ScreenSaver on the session bus so apps playing video can keep
# the screensaver from firing (issue #6475).
if [[ -f $OMARCHY_PATH/default/systemd/user/omarchy-idle-inhibit.service ]]; then
  systemctl --user enable --now omarchy-idle-inhibit.service >/dev/null 2>&1 || true
fi
