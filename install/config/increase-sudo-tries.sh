OMARCHY_DESCRIPTION="Sudo lockout limit"

omarchy_install() {
  # Give the user 10 instead of 3 tries to fat finger their password before lockout
  echo "Defaults passwd_tries=10" | sudo tee /etc/sudoers.d/passwd-tries
  sudo chmod 440 /etc/sudoers.d/passwd-tries
}

omarchy_verify() {
  sudo test -f /etc/sudoers.d/passwd-tries || add_error "Sudoers passwd-tries file missing"

  if sudo test -f /etc/sudoers.d/passwd-tries; then
    local perms=$(sudo stat -c %a /etc/sudoers.d/passwd-tries)
    [[ "$perms" == "440" ]] || add_error "Sudoers file has incorrect permissions: $perms (should be 440)"

    sudo grep -q "passwd_tries=10" /etc/sudoers.d/passwd-tries || add_error "Passwd tries not set to 10"
  fi
}
