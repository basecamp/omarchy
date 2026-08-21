echo "Give the session slice CPU priority over apps so builds cannot stall input"

# New installs get /usr/lib/systemd/user/session.slice.d/10-cpuweight.conf
# with the package. Existing sessions only apply a slice drop-in when the user
# manager reloads, and the weight takes effect live -- no relogin needed.
# An `omarchy update` from SSH or a TTY has no user manager to reload; there
# the next graphical login picks it up on its own.
systemctl --user daemon-reload >/dev/null 2>&1 || true
