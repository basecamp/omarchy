echo "Announce networks that need a captive portal sign-in"

# install/user/first-run/enable-user-units.sh is skipped after the first login,
# so existing installs need the unit enabled here.

systemctl --user daemon-reload >/dev/null 2>&1 || true

# `systemctl enable` needs a live user manager, which an update from a TTY does
# not have, so fall back to writing the symlink it would have written.
if ! systemctl --user enable omarchy-network-portal-watch.service >/dev/null 2>&1; then
  wants_dir="$HOME/.config/systemd/user/graphical-session.target.wants"
  mkdir -p "$wants_dir"
  ln -sfn /usr/lib/systemd/user/omarchy-network-portal-watch.service \
    "$wants_dir/omarchy-network-portal-watch.service"
fi

# Nothing to start into over SSH; the next graphical login handles it. A failed
# start only delays portal toasts, so it stays quiet.
if systemctl --user is-active --quiet graphical-session.target; then
  systemctl --user start omarchy-network-portal-watch.service >/dev/null 2>&1 || true
fi
