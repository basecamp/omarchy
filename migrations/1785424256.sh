echo "Let systemd-oomd kill a runaway app instead of the whole session"

# New installs get this from install/config/enable-services.sh. Existing ones
# have never had an OOM daemon, so nothing stands between memory pressure and
# the session falling over.

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

# Machine-wide, so a second user on the same box finds it already done.
if systemctl is-enabled --quiet systemd-oomd.service 2>/dev/null; then
  # Already enabled means it started before the package delivered our
  # thresholds in /etc/systemd/oomd.conf.d/, and oomd only reads that at
  # startup. Restart so it doesn't run with stale limits until reboot.
  as_root systemctl try-restart systemd-oomd.service >/dev/null 2>&1 || true
else
  as_root systemctl enable --now systemd-oomd.service >/dev/null 2>&1 ||
    echo "Could not enable systemd-oomd.service; memory pressure will still take the session down."
fi

# Run the user generator and pick up app.slice candidacy without waiting for
# the next login. The generator skips the drop-in when procfs hides PID 1,
# because systemd cannot resolve ManagedOOM dependencies in that setup. An
# `omarchy update` over SSH or from a TTY has no user manager to reload, and
# there the next graphical login runs the generator on its own.
systemctl --user daemon-reload >/dev/null 2>&1 || true
