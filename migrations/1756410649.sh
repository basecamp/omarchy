echo "Remove any Chaotic-AUR infrastructure packages"

if pacman -Q chaotic-keyring >/dev/null; then
  sudo pacman -Rns --noconfirm chaotic-keyring
fi

if pacman -Q chaotic-mirrorlist >/dev/null; then
  sudo pacman -Rns --noconfirm chaotic-mirrorlist
fi

sudo pacman-key --delete 3056513887B78AEB
