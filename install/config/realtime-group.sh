# Let the compositor and the audio graph ask the kernel for realtime priority.
# Hyprland calls sched_setscheduler on its own event thread at boot and PipeWire
# asks module-rt for rt.prio 88; both need RLIMIT_RTPRIO on the systemd user
# manager, which pam_limits reads from realtime-privileges' limits.d file for
# members of the realtime group. Without the membership both requests fail and
# the desktop runs every thread as SCHED_OTHER.
#
# Recorded for provisioning first-boot user creation and factory reset, granted
# directly when the install user already exists (deferred-provisioning installs
# create the user at first boot instead).
provisioning_dir="${OMARCHY_PROVISIONING_DIR:-/var/lib/omarchy/provisioning}"
mkdir -p "$provisioning_dir"
grep -qxF realtime "$provisioning_dir/groups" 2>/dev/null || echo realtime >>"$provisioning_dir/groups"

# Unlike input, realtime is created by a package rather than by systemd, so it
# is only there once realtime-privileges is in. A run that gets here without it
# would abort the whole system setup on the usermod; the provisioning record
# above still covers the user created at first boot.
if getent group realtime >/dev/null &&
  [[ -n ${OMARCHY_INSTALL_USER:-} ]] && getent passwd "$OMARCHY_INSTALL_USER" >/dev/null; then
  usermod -aG realtime "$OMARCHY_INSTALL_USER"
fi
