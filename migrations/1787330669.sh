echo "Reconnect trusted Bluetooth keyboards and mice at login"

systemctl --user daemon-reload >/dev/null 2>&1 || true

# Enable without --now, and start by hand further down only when there is a
# session to start into. `systemctl enable` needs a live user manager, which an
# `omarchy update` from a TTY or over SSH does not have, so fall back to writing
# exactly the symlink it would have written rather than printing an error and
# marking the migration complete with the unit still unenabled.
if ! systemctl --user enable omarchy-bluetooth-reconnect.service >/dev/null 2>&1; then
  wants_dir="$HOME/.config/systemd/user/graphical-session.target.wants"
  mkdir -p "$wants_dir"
  ln -sfn /usr/lib/systemd/user/omarchy-bluetooth-reconnect.service \
    "$wants_dir/omarchy-bluetooth-reconnect.service"
fi

# This unit belongs to the login: the peripherals it asks for are the ones
# someone is about to type on. Starting it from an update over SSH would reach
# for the keyboard and mouse of whoever is sitting at the machine, mid-update,
# so leave it to the next graphical login.
if systemctl --user is-active --quiet graphical-session.target; then
  # A failed start only leaves the peripherals where they already were, one
  # click away in the Bluetooth panel, until the next login picks them up.
  systemctl --user start omarchy-bluetooth-reconnect.service >/dev/null 2>&1 || true
fi
