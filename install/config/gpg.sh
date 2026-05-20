# etc/gnupg/dirmngr.conf ships via omarchy-settings. Restart dirmngr so it
# picks up the new keyserver list and timeout.
sudo gpgconf --kill dirmngr || true
sudo gpgconf --launch dirmngr || true
