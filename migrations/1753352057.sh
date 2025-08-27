echo "Add Chaotic-AUR to get compiled binaries"

if [[ "$(uname -m)" == "x86_64" ]] && ! grep -q '^\[chaotic-aur\]' /etc/pacman.conf; then
  # Try installing Chaotic-AUR keyring and mirrorlist
  if sudo pacman-key --recv-key 3056513887B78AEB &&
    sudo pacman-key --lsign-key 3056513887B78AEB &&
    sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' &&
    sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'; then

    # Add Chaotic-AUR repo to pacman config
    echo -e '\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist' | sudo tee -a /etc/pacman.conf >/dev/null

    # Refresh pacman package databases
    sudo pacman -Syu
  else
    echo "Failed to install Chaotic-AUR, so won't include it in pacman config!"
  fi
fi
