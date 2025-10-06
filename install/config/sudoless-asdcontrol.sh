OMARCHY_DESCRIPTION="ASDControl Sudoless Brightness Control"

omarchy_install() {
  # Setup sudo-less controls for controlling brightness on Apple Displays
  echo "$USER ALL=(ALL) NOPASSWD: /usr/local/bin/asdcontrol" | sudo tee /etc/sudoers.d/asdcontrol
  sudo chmod 440 /etc/sudoers.d/asdcontrol
}

omarchy_verify() {
  sudo test -f /etc/sudoers.d/asdcontrol || add_error "ASDControl sudoers file missing"

  if sudo test -f /etc/sudoers.d/asdcontrol; then
    local perms=$(sudo stat -c %a /etc/sudoers.d/asdcontrol)
    [[ "$perms" == "440" ]] || add_error "Sudoers file has incorrect permissions: $perms (should be 440)"

    sudo grep -q "NOPASSWD: /usr/local/bin/asdcontrol" /etc/sudoers.d/asdcontrol || add_error "ASDControl sudoers rule not configured"
  fi
}
