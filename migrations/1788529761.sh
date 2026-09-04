echo "Notify when updates are available for installed apps and tools"

# The timer is enabled at first-run in install/user/first-run/enable-user-units.sh,
# which only runs once, so existing installs need it enabled here.

systemctl --user daemon-reload >/dev/null 2>&1 || true

# `systemctl enable` needs a live user manager, which an update from a TTY does
# not have, so fall back to writing the symlink it would have written.
if ! systemctl --user enable omarchy-update-notify.timer >/dev/null 2>&1; then
  wants_dir="$HOME/.config/systemd/user/timers.target.wants"
  mkdir -p "$wants_dir"
  ln -sfn /usr/lib/systemd/user/omarchy-update-notify.timer \
    "$wants_dir/omarchy-update-notify.timer"
fi

# Nothing to start into over SSH; the next graphical login handles it. A failed
# start only delays the first update toast, so it stays quiet.
if systemctl --user is-active --quiet graphical-session.target; then
  systemctl --user start omarchy-update-notify.timer >/dev/null 2>&1 || true
fi
