OMARCHY_DESCRIPTION="Powerprofilesctl"

omarchy_install() {
  # Ensure we use system python3 and not mise's python3
  sudo sed -i '/env python3/ c\#!/bin/python3' /usr/bin/powerprofilesctl
}

omarchy_verify() {
  [[ -f /usr/bin/powerprofilesctl ]] || add_error "powerprofilesctl not found"

  if [[ -f /usr/bin/powerprofilesctl ]]; then
      head -n1 /usr/bin/powerprofilesctl | grep -q "^#!/bin/python3$" || add_error "powerprofilesctl shebang not fixed"
  fi
}
