# Give this user privileged input access for dictation tools + xbox controllers to work
usermod -aG input "${OMARCHY_INSTALL_USER:-${USER:-}}"
