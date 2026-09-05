echo "Install fingerprint recovery after resume"

hook_src="${OMARCHY_FPRINTD_RESUME_SRC:-$OMARCHY_PATH/default/systemd/system-sleep/fprintd-resume-stop}"
hook_dst="${OMARCHY_FPRINTD_RESUME_DST:-/usr/lib/systemd/system-sleep/fprintd-resume-stop}"
lock_pam="${OMARCHY_LOCK_FINGERPRINT_PAM:-/etc/pam.d/omarchy-lock-fingerprint}"

# Fingerprint setup is per-machine, while migration completion is per-user.
# Install once on configured machines and let later users no-op.
[[ -f $lock_pam && -f $hook_src && ! -e $hook_dst ]] || exit 0

echo "Installing fingerprint resume recovery"
sudo install -Dm755 "$hook_src" "$hook_dst"
