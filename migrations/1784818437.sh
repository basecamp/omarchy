echo "Gate polkit fingerprint auth behind the lid state (password when the lid is shut)"

# Existing fingerprint setups have pam_fprintd first in /etc/pam.d/polkit-1 but
# no lid gate, so a closed-lid pkexec would block on the unreachable reader for
# the full pam_fprintd timeout before offering the password. Insert a pam_exec
# gate before pam_fprintd that skips fingerprint while the lid is closed. New
# setups already get this from omarchy-setup-security-fingerprint.
#
# The gate points at the fixed /usr/bin path the omarchy package always
# provides, so it keeps working across package installs and dev-link (which
# overlays $OMARCHY_PATH but leaves /usr/bin untouched). pam_exec needs a
# literal absolute path — it does not expand env vars.

polkit_pam="/etc/pam.d/polkit-1"
gate="auth      [success=1 default=ignore] pam_exec.so quiet /usr/bin/omarchy-hw-laptop-closed"

if [[ -f $polkit_pam ]] &&
  grep -q 'pam_fprintd\.so' "$polkit_pam" &&
  ! grep -q 'omarchy-hw-laptop-closed' "$polkit_pam"; then
  sudo sed -i "/pam_fprintd\.so/i $gate" "$polkit_pam"
fi
