# Starting the installer with OMARCHY_CHROOT_INSTALL=1 will put it into chroot mode
chrootable_systemctl_enable() {
  if [[ -n ${OMARCHY_CHROOT_INSTALL:-} ]]; then
    sudo systemctl enable $1
  else
    sudo systemctl enable --now $1
  fi
}

# Like chrootable_systemctl_enable but never passes --now, so the service is
# only enabled for the next boot. Use for services that are either already
# running (and re-starting would interrupt the install — iwd) or that shouldn't
# auto-start during install (docker, power-profiles-daemon).
chrootable_systemctl_enable_only() {
  sudo systemctl enable $1
}

# Export the functions so they're available in subshells
export -f chrootable_systemctl_enable
export -f chrootable_systemctl_enable_only
