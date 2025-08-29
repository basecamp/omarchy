echo "Remove any Chaotic-AUR infrastructure packages"

pkg-remove chaotic-keyring chaotic-mirrorlist

if sudo pacman-key --list-keys 3056513887B78AEB >/dev/null 2>&1; then
  sudo pacman-key --delete 3056513887B78AEB
fi
