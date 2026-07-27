echo "Supervise fcitx5 so CapsLock compose sequences can't silently die"

# fcitx5 was launched fire-and-forget from Hyprland's autostart. Nothing
# restarted it and nothing noticed when it went away, so a single lost start
# left every ~/.XCompose sequence (CapsLock m s -> emoji) dead for the rest of
# the session. It's a systemd user service with Restart=always now.

systemctl --user daemon-reload >/dev/null 2>&1 || true

# Enable without --now, and start by hand further down only when there is a
# session to start into. `systemctl enable` needs a live user manager, which an
# `omarchy update` from a TTY does not have, so fall back to writing exactly the
# symlink it would have written rather than silently leaving this unenabled.
if ! systemctl --user enable omarchy-fcitx5.service >/dev/null 2>&1; then
  wants_dir="$HOME/.config/systemd/user/graphical-session.target.wants"
  mkdir -p "$wants_dir"
  ln -sfn /usr/lib/systemd/user/omarchy-fcitx5.service \
    "$wants_dir/omarchy-fcitx5.service"
fi

# Outside a graphical session -- an update over SSH -- there is nothing to hand
# over: no autostart-launched fcitx5 to kill, and the unit's own
# ConditionEnvironment would skip the start anyway. The enablement above is the
# whole job; the next graphical login starts it.
if systemctl --user is-active --quiet graphical-session.target; then
  # The service and the autostart-launched process can't coexist: a second
  # fcitx5 sees the first owning org.fcitx.Fcitx5 and exits 0, which
  # Restart=always would turn into a restart loop. Drop the stray first.
  pkill -x fcitx5 >/dev/null 2>&1 || true

  # Report what systemctl actually said. This kills a fcitx5 that was working a
  # moment ago, so a start failure here has to be loud instead of leaving the
  # session with no input method and a migration marked complete.
  if ! error=$(systemctl --user start omarchy-fcitx5.service 2>&1); then
    echo "Could not start omarchy-fcitx5.service: $error"
    echo "Compose sequences (CapsLock m s) will not work until the next login."
  fi
fi
