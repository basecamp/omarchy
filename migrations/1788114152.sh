echo "Run the Herdr server as a graphical-session user unit"

# The Herdr server permanently inherits the environment of whoever starts it,
# and the CLI auto-starts one on first contact from wherever that happens to
# be. After a reboot that can be an SSH login with no WAYLAND_DISPLAY, leaving
# every pane and agent without Wayland clipboard access and crashing GUI
# launches (herdrdev/herdr#2448, #2859). The unit gives the server one defined
# birth inside the graphical session; SSH logins then attach instead of
# spawning a broken server.
#
# Enable only, without --now: a CLI-started server is very likely running right
# now — probably hosting the pane this update runs in — and a second server
# would fight it for the socket. The unit takes over at the next login, when
# the old server is gone; PartOf keeps the handover clean from then on.
systemctl --user daemon-reload >/dev/null 2>&1 || true

# Report what systemctl actually said; "could not enable" on its own gives
# nothing to act on.
if ! error=$(systemctl --user enable herdr.service 2>&1); then
  echo "Could not enable herdr.service: $error"
fi
