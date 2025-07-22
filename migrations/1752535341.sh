echo "Setting up GPG configuration with multiple keyservers for better reliability"

if [[ ! -f /etc/gnupg/dirmngr.conf ]]; then
  sudo mkdir -p /etc/gnupg
  sudo cp ~/.local/share/omarchy/default/gpg/dirmngr.conf /etc/gnupg/
  sudo chmod 644 /etc/gnupg/dirmngr.conf
  sudo gpgconf --kill dirmngr || true
  sudo gpgconf --launch dirmngr || true
fi
