# Installs are followed by reboot, so enable units without starting/reloading
# running services during the install.
chrootable_systemctl_enable() {
  sudo systemctl enable $1
}

chrootable_systemctl_enable_only() {
  sudo systemctl enable $1
}

export -f chrootable_systemctl_enable
export -f chrootable_systemctl_enable_only
