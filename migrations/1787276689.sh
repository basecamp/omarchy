echo "Give the session slice CPU priority over apps so builds cannot stall input"

# New installs get /usr/lib/systemd/user/session.slice.d/10-cpuweight.conf
# with omarchy-settings. Existing sessions only apply a slice drop-in when the
# user manager reloads, and the weight takes effect live -- no relogin needed.
# There is one user manager per user, not per session, so this also reaches
# the graphical session when `omarchy update` runs from SSH or a TTY.
systemctl --user daemon-reload >/dev/null 2>&1 || true

# Migrations run once. If this one lands before the package that ships the
# drop-in, apply the same weight for the running user manager only. --runtime
# writes /run/user/$UID/systemd/user.control/session.slice.d/50-CPUWeight.conf,
# which outlives nothing but the manager itself (it is gone once the user has
# fully logged out), so the packaged file takes over from the next login on
# without a second migration. Until then the runtime drop-in sorts after and
# outranks the packaged one; both say 1000, so nothing differs.
if [[ ! -f /usr/lib/systemd/user/session.slice.d/10-cpuweight.conf ]]; then
  systemctl --user set-property --runtime session.slice CPUWeight=1000 >/dev/null 2>&1 || true
fi
