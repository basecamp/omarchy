# Record the docker group for OEM first-boot user creation and factory reset,
# then grant it directly when the install user already exists (OEM-mode
# installs create the user at first boot instead).
oem_dir="${OMARCHY_OEM_DIR:-/var/lib/omarchy/oem}"
mkdir -p "$oem_dir"
grep -qxF docker "$oem_dir/groups" 2>/dev/null || echo docker >>"$oem_dir/groups"

if [[ -n ${OMARCHY_INSTALL_USER:-} ]] && getent passwd "$OMARCHY_INSTALL_USER" >/dev/null; then
  usermod -aG docker "$OMARCHY_INSTALL_USER"
fi
