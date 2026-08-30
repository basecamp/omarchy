echo "Install the fingerprint resume hook on existing fingerprint setups"

# omarchy-setup-security-fingerprint gained a system-sleep hook that restarts
# fprintd on resume, so a verify wedged by suspend cannot leave the reader dead
# on the lock screen, and a drop-in bounding fprintd's stop timeout so that
# restart lands within seconds even when the daemon ignores SIGTERM. New setups
# install both; a machine that enrolled a finger before they existed never
# re-runs setup, so drop them in here.

hook_src="${OMARCHY_FPRINTD_RESUME_SRC:-$OMARCHY_PATH/default/systemd/system-sleep/fprintd-resume}"
hook_dst="${OMARCHY_FPRINTD_RESUME_DST:-/usr/lib/systemd/system-sleep/fprintd-resume}"
stop_timeout_src="${OMARCHY_FPRINTD_STOP_TIMEOUT_SRC:-$OMARCHY_PATH/default/systemd/system/fprintd.service.d/10-stop-timeout.conf}"
stop_timeout_dst="${OMARCHY_FPRINTD_STOP_TIMEOUT_DST:-/etc/systemd/system/fprintd.service.d/10-stop-timeout.conf}"
lock_pam="${OMARCHY_LOCK_FINGERPRINT_PAM:-/etc/pam.d/omarchy-lock-fingerprint}"

# Only where fingerprint is configured, and only what is absent -- an existing
# copy may be newer or hand-edited, so leave it alone. install -Dm755 sets the
# executable bit explicitly, which systemd-sleep requires to run the hook.
[[ -f $lock_pam ]] || exit 0

if [[ -f $hook_src && ! -e $hook_dst ]]; then
  echo "Installing the fprintd resume hook"
  sudo install -Dm755 "$hook_src" "$hook_dst"
fi

# An earlier build of this shipped the drop-in without the numeric prefix,
# where it outranked an administrator's override.conf; replace that copy.
legacy_stop_timeout="${stop_timeout_dst%/*}/stop-timeout.conf"
if [[ -f $stop_timeout_src && ( -e $legacy_stop_timeout || ! -e $stop_timeout_dst ) ]]; then
  echo "Bounding fprintd's stop timeout"
  sudo rm -f "$legacy_stop_timeout"
  sudo install -Dm644 "$stop_timeout_src" "$stop_timeout_dst"
  sudo systemctl daemon-reload
fi
