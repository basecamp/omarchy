echo "Give the session slice CPU priority over apps so builds cannot stall input"

# New installs get /usr/lib/systemd/user/session.slice.d/10-cpuweight.conf
# with omarchy-settings. Existing sessions only apply a slice drop-in when the
# user manager reloads, and the weight takes effect live -- no relogin needed.
# An `omarchy update` from SSH or a TTY has no user manager to reload; there
# the next graphical login picks it up on its own.
systemctl --user daemon-reload >/dev/null 2>&1 || true

# Migrations run once. If this one lands before the package that ships the
# drop-in, apply the same weight for the running session only (--runtime
# writes under /run, nothing persists), so the user gets it now and the
# packaged file takes over at the next login without a second migration.
if [[ ! -f /usr/lib/systemd/user/session.slice.d/10-cpuweight.conf ]]; then
  systemctl --user set-property --runtime session.slice CPUWeight=1000 >/dev/null 2>&1 || true
fi
