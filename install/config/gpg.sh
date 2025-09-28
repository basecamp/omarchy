OMARCHY_DESCRIPTION="GPG"

omarchy_install() {
  # Setup GPG configuration with multiple keyservers for better reliability
  sudo mkdir -p /etc/gnupg
  sudo cp ~/.local/share/omarchy/default/gpg/dirmngr.conf /etc/gnupg/
  sudo chmod 644 /etc/gnupg/dirmngr.conf
  sudo gpgconf --kill dirmngr || true
  sudo gpgconf --launch dirmngr || true
}

omarchy_verify() {
  [[ -d /etc/gnupg ]] || add_error "GPG config directory missing"
  [[ -f /etc/gnupg/dirmngr.conf ]] || add_error "GPG dirmngr.conf missing"

  if [[ -f /etc/gnupg/dirmngr.conf ]]; then
    local perms=$(stat -c %a /etc/gnupg/dirmngr.conf)
    [[ "$perms" == "644" ]] || add_error "GPG dirmngr.conf has incorrect permissions: $perms (should be 644)"
  fi
}
