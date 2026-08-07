# Give this user privileged input access for dictation tools + xbox controllers to work.
# Recorded for OEM first-boot user creation and factory reset, granted directly
# when the install user already exists (OEM-mode installs create the user at
# first boot instead).
oem_dir="${OMARCHY_OEM_DIR:-/var/lib/omarchy/oem}"
mkdir -p "$oem_dir"
grep -qxF input "$oem_dir/groups" 2>/dev/null || echo input >>"$oem_dir/groups"

if [[ -n ${OMARCHY_INSTALL_USER:-} ]] && getent passwd "$OMARCHY_INSTALL_USER" >/dev/null; then
  usermod -aG input "$OMARCHY_INSTALL_USER"
fi
