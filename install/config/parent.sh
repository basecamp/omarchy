# A child install (kids mode) keeps root for the parent: omarchy-parent apply
# points sudo and polkit at root's password and moves the kid account out of
# wheel. A deferred child install has no user yet; first-boot provisioning
# makes the same call once it has created one and set root's password.
if [[ ${OMARCHY_INSTALL_PROFILE:-default} == "child" && -n ${OMARCHY_INSTALL_USER:-} ]]; then
  omarchy-parent apply --user "$OMARCHY_INSTALL_USER"
fi
