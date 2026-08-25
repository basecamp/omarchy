echo "Show keyboard backlight OSD and mirror it to the GZ302 chassis window LED"

systemctl --user daemon-reload >/dev/null 2>&1 || true

if ! systemctl --user enable omarchy-brightness-keyboard-watch.service >/dev/null 2>&1; then
  wants_dir="$HOME/.config/systemd/user/graphical-session.target.wants"
  mkdir -p "$wants_dir"
  ln -sfn /usr/lib/systemd/user/omarchy-brightness-keyboard-watch.service \
    "$wants_dir/omarchy-brightness-keyboard-watch.service"
fi

if systemctl --user is-active --quiet graphical-session.target; then
  systemctl --user start omarchy-brightness-keyboard-watch.service >/dev/null 2>&1 || true
fi
