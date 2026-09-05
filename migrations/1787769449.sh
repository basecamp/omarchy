echo "Enable the D-Bus idle inhibit daemon so browser video playback stops triggering the screensaver"

# Quattro's idle service honors only the Wayland idle-inhibit protocol, and
# nothing has owned org.freedesktop.ScreenSaver since hypridle was replaced —
# so an inhibit requested over D-Bus (every browser playing video, VLC) was
# dropped and the screensaver fired over the playing video. The new
# omarchy-idle-inhibit-daemon owns those names and publishes its state for the
# idle service to hold its cycles.

# Enable without --now: this usually runs inside `omarchy update`, where
# starting the daemon is harmless but pointless half a second before the
# session restarts. `systemctl enable` needs a live user manager, which
# `omarchy update` over SSH does not have, so fall back to writing precisely
# the symlink it would have written rather than silently doing nothing.
systemctl --user daemon-reload >/dev/null 2>&1 || true

if ! systemctl --user enable omarchy-idle-inhibit.service >/dev/null 2>&1; then
  wants_dir="$HOME/.config/systemd/user/graphical-session.target.wants"
  mkdir -p "$wants_dir"
  ln -sfn /usr/lib/systemd/user/omarchy-idle-inhibit.service \
    "$wants_dir/omarchy-idle-inhibit.service"
fi
