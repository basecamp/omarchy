echo "Keep the mute LEDs in step with PipeWire on laptops that have them"

# The kernel's audio-mute LED trigger is attached on some laptops but never
# fires, so muting left the speaker LED dark. Driving it from the mute commands
# would only cover the keybindings, since the bar's audio panel sets the
# PipeWire node directly. omarchy-audio-mute-led-watch follows PipeWire instead.
#
# The unit's own ConditionPathExists keeps it inert on hardware without the LED
# nodes, so this is safe to enable everywhere.

systemctl --user daemon-reload >/dev/null 2>&1 || true

# `systemctl enable` needs a live user manager, which an `omarchy update` from a
# TTY does not have. Fall back to writing exactly the symlink it would have
# written rather than silently leaving this unenabled.
if ! systemctl --user enable omarchy-audio-mute-led-watch.service >/dev/null 2>&1; then
  wants_dir="$HOME/.config/systemd/user/graphical-session.target.wants"
  mkdir -p "$wants_dir"
  ln -sfn /usr/lib/systemd/user/omarchy-audio-mute-led-watch.service \
    "$wants_dir/omarchy-audio-mute-led-watch.service"
fi

# Outside a graphical session there is nothing to start into, and the unit's
# conditions would skip it anyway. The next login starts it.
if systemctl --user is-active --quiet graphical-session.target; then
  systemctl --user start omarchy-audio-mute-led-watch.service >/dev/null 2>&1 || true
fi
