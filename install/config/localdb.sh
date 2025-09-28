OMARCHY_DESCRIPTION="LocalDB"

omarchy_install() {
  # Update localdb so that locate will find everything installed
  sudo updatedb
}

omarchy_verify() {
  [[ -f /var/lib/mlocate/mlocate.db ]] || [[ -f /var/lib/plocate/plocate.db ]] || add_error "Locate database missing"

  command -v locate >/dev/null 2>&1 || add_error "Locate command not available"
}
