# Record the docker group for provisioning first-boot user creation and factory reset,
# then grant it directly when the install user already exists (deferred-provisioning
# installs create the user at first boot instead).
provisioning_dir="${OMARCHY_PROVISIONING_DIR:-/var/lib/omarchy/provisioning}"
mkdir -p "$provisioning_dir"
grep -qxF docker "$provisioning_dir/groups" 2>/dev/null || echo docker >>"$provisioning_dir/groups"

if [[ -n ${OMARCHY_INSTALL_USER:-} ]] && getent passwd "$OMARCHY_INSTALL_USER" >/dev/null; then
  usermod -aG docker "$OMARCHY_INSTALL_USER"
fi
