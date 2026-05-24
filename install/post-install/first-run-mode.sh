# Setup sudo-less access for the privileged first-run system one-shot. The
# install user's ~/.local/state/omarchy/first-run.mode marker is created by
# finalize.sh while running as that user.
install_user="$OMARCHY_INSTALL_USER"
install_mode_is offline || exit 0

mkdir -p /etc/sudoers.d
cat > /etc/sudoers.d/first-run <<EOF
Cmnd_Alias FIRST_RUN_CLEANUP = /usr/bin/rm -f /etc/sudoers.d/first-run, /bin/rm -f /etc/sudoers.d/first-run
Cmnd_Alias SYMLINK_RESOLVED = /usr/bin/ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
$install_user ALL=(ALL) NOPASSWD: /usr/bin/systemctl
$install_user ALL=(ALL) NOPASSWD: /usr/bin/ufw
$install_user ALL=(ALL) NOPASSWD: /usr/bin/ufw-docker
$install_user ALL=(ALL) NOPASSWD: /usr/bin/gtk-update-icon-cache
$install_user ALL=(ALL) NOPASSWD: SYMLINK_RESOLVED
$install_user ALL=(ALL) NOPASSWD: FIRST_RUN_CLEANUP
EOF
chmod 440 /etc/sudoers.d/first-run
