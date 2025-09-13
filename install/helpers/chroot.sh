# Starting the installer with OMARCHY_CHROOT_INSTALL=1 will put it into chroot mode
chrootable_systemctl_enable() {
  if [ -n "${OMARCHY_CHROOT_INSTALL:-}" ]; then
    sudo systemctl enable $1
  else
    sudo systemctl enable --now $1
  fi
}

# Export the function so it's available in subshells
export -f chrootable_systemctl_enable
