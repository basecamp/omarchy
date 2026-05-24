# Allow passwordless reboot for the online installer - removed in first-run
install_user="${OMARCHY_INSTALL_USER:-${USER:-}}"
[[ -n $install_user ]] || exit 0

mkdir -p /etc/sudoers.d
cat > /etc/sudoers.d/99-omarchy-installer-reboot <<EOF
Cmnd_Alias INSTALLER_REBOOT_CLEANUP = /usr/bin/rm -f /etc/sudoers.d/99-omarchy-installer-reboot, /bin/rm -f /etc/sudoers.d/99-omarchy-installer-reboot
$install_user ALL=(ALL) NOPASSWD: /usr/bin/reboot
$install_user ALL=(ALL) NOPASSWD: INSTALLER_REBOOT_CLEANUP
EOF
chmod 440 /etc/sudoers.d/99-omarchy-installer-reboot
