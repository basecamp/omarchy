echo "Install the fingerprint resume hook on existing fingerprint setups"

# omarchy-setup-security-fingerprint gained a system-sleep hook that restarts
# fprintd on resume, so a verify wedged by suspend cannot leave the reader dead
# on the lock screen. New setups install it; a machine that enrolled a finger
# before the hook existed never re-runs setup, so drop it in here.

hook_src="${OMARCHY_FPRINTD_RESUME_SRC:-$OMARCHY_PATH/default/systemd/system-sleep/fprintd-resume}"
hook_dst="${OMARCHY_FPRINTD_RESUME_DST:-/usr/lib/systemd/system-sleep/fprintd-resume}"
lock_pam="${OMARCHY_LOCK_FINGERPRINT_PAM:-/etc/pam.d/omarchy-lock-fingerprint}"

# Only where fingerprint is configured, and only when the hook is absent -- an
# existing copy may be newer or hand-edited, so leave it alone. install -Dm755
# sets the executable bit explicitly, which systemd-sleep requires to run it.
[[ -f $lock_pam && -f $hook_src && ! -e $hook_dst ]] || exit 0

echo "Installing the fprintd resume hook"
sudo install -Dm755 "$hook_src" "$hook_dst"
