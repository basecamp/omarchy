echo "Add Chaotic-AUR to get compiled binaries"

if [[ "$(uname -m)" == "x86_64" ]] && ! grep -q '^\[chaotic-aur\]' /etc/pacman.conf; then
  # Import Chaotic-AUR key
  sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
  sudo pacman-key --lsign-key 3056513887B78AEB

  # Install Chaotic-AUR keyring and mirrorlist
  sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
  sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

  if [[ -f /etc/pacman.d/chaotic-mirrorlist ]]; then
    # Add Chaotic-AUR repo to pacman config
    echo -e '\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist' | sudo tee -a /etc/pacman.conf >/dev/null
  else
    echo "Failed to download chaotic-mirrorlist, so won't include it in pacman config!"
  fi

  # Refresh pacman package databases
  sudo pacman -Sy
fi
