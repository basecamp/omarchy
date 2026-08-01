echo "Fix D-Bus idle inhibits (org.freedesktop.ScreenSaver) being silently dropped during video playback"

# Quattro's Quickshell idle service only understands the Wayland
# idle-inhibit protocol (IdleMonitor { respectInhibitors: true }). Nothing
# replaced hypridle's ownership of org.freedesktop.ScreenSaver on the session
# bus, so every D-Bus Inhibit() call from browsers and video players was
# silently dropped and the screensaver/lock fired mid-playback (#6475).
#
# omarchy-system-idle-inhibit-bridge now owns that bus name and forwards
# inhibit state to the idle service's IPC target.

systemctl --user daemon-reload >/dev/null 2>&1 || true

# Enable without --now, and start by hand further down only when there is a
# session to start into, matching the fcitx5 migration: `systemctl enable`
# needs a live user manager, which an `omarchy update` from a TTY does not
# have, so fall back to writing exactly the symlink it would have written
# rather than silently leaving this unenabled.
if ! systemctl --user enable omarchy-idle-inhibit-bridge.service >/dev/null 2>&1; then
  wants_dir="$HOME/.config/systemd/user/graphical-session.target.wants"
  mkdir -p "$wants_dir"
  ln -sfn /usr/lib/systemd/user/omarchy-idle-inhibit-bridge.service \
    "$wants_dir/omarchy-idle-inhibit-bridge.service"
fi

# Outside a graphical session (an update over SSH) there is nothing to start
# into: the unit's own ConditionEnvironment would skip the start anyway, and
# the next graphical login starts it. The enablement above is the whole job.
if systemctl --user is-active --quiet graphical-session.target; then
  if ! error=$(systemctl --user start omarchy-idle-inhibit-bridge.service 2>&1); then
    echo "Could not start omarchy-idle-inhibit-bridge.service: $error"
    echo "D-Bus idle inhibits (video players, browsers) will not be honored until the next login."
  fi
fi
