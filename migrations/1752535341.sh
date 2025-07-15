echo "Setting up GPG configuration with multiple keyservers for better reliability"
sudo mkdir -p /etc/gnupg
sudo cp ~/.local/share/omarchy/default/gpg/dirmngr.conf /etc/gnupg/
sudo chmod 644 /etc/gnupg/dirmngr.conf
sudo gpgconf --kill dirmngr || true
