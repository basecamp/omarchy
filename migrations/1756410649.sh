echo "Remove any Chaotic-AUR infrastructure packages"

if pacman -Q chaotic-keyring 2>/dev/null; then
  sudo pacman -Rns --noconfirm chaotic-keyring
fi

if pacman -Q chaotic-mirrorlist 2>/dev/null; then
  sudo pacman -Rns --noconfirm chaotic-mirrorlist
fi

if sudo pacman-key --list-keys 3056513887B78AEB >/dev/null 2>&1; then
  sudo pacman-key --delete 3056513887B78AEB
fi
