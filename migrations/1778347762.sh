echo "Restrict first-run systemctl sudo access"

if ! sudo -v; then
  echo "Failed to obtain sudo privileges for first-run sudoers migration" >&2
  exit 1
fi

if sudo test -f /etc/sudoers.d/first-run && sudo grep -q 'NOPASSWD: /usr/bin/systemctl' /etc/sudoers.d/first-run; then
  first_run_user="$(sudo awk '/NOPASSWD:/ { print $1; exit }' /etc/sudoers.d/first-run)"
  if [[ -z $first_run_user ]]; then
    echo "Failed to determine existing first-run sudoers user" >&2
    exit 1
  fi

  sudo tee /etc/sudoers.d/first-run >/dev/null <<EOF
Cmnd_Alias FIRST_RUN_CLEANUP = /bin/rm -f /etc/sudoers.d/first-run
Cmnd_Alias INSTALLER_REBOOT_CLEANUP = /bin/rm -f /etc/sudoers.d/99-omarchy-installer-reboot
Cmnd_Alias SYMLINK_RESOLVED = /usr/bin/ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
Cmnd_Alias UFW_SERVICE_ENABLE = /usr/bin/systemctl enable ufw
$first_run_user ALL=(ALL) NOPASSWD: UFW_SERVICE_ENABLE
$first_run_user ALL=(ALL) NOPASSWD: /usr/bin/ufw
$first_run_user ALL=(ALL) NOPASSWD: /usr/bin/ufw-docker
$first_run_user ALL=(ALL) NOPASSWD: /usr/bin/gtk-update-icon-cache
$first_run_user ALL=(ALL) NOPASSWD: SYMLINK_RESOLVED
$first_run_user ALL=(ALL) NOPASSWD: FIRST_RUN_CLEANUP
$first_run_user ALL=(ALL) NOPASSWD: INSTALLER_REBOOT_CLEANUP
EOF
  sudo chmod 440 /etc/sudoers.d/first-run
fi
