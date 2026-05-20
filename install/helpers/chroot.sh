# Starting the installer with OMARCHY_CHROOT_INSTALL=1 will put it into chroot mode
chrootable_systemctl_enable() {
  if [[ -n ${OMARCHY_CHROOT_INSTALL:-} ]]; then
    sudo systemctl enable $1
  else
    sudo systemctl enable --now $1
  fi
}

# Like chrootable_systemctl_enable but never passes --now. Use for services
# we shouldn't (re)start mid-install (iwd interrupts the network; docker and
# power-profiles-daemon should defer to first boot).
chrootable_systemctl_enable_only() {
  sudo systemctl enable $1
}

export -f chrootable_systemctl_enable
export -f chrootable_systemctl_enable_only
