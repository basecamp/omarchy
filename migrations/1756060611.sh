echo "Migrate AUR packages to official repos where possible"

if command -v obsidian >/dev/null; then
  sudo pacman -Rns --noconfirm obsidian-bin
  sudo pacman -S --noconfirm obsidian
fi

if command -v localsend >/dev/null; then
  sudo pacman -Rns --noconfirm localsend-bin
  sudo pacman -S --noconfirm localsend
fi

if pacman -Q omarchy-chromium-bin >/dev/null; then
  sudo pacman -Rns --noconfirm omarchy-chromium-bin
  sudo pacman -S --noconfirm omarchy-chromium
fi

if pacman -Q walker-bin >/dev/null; then
  sudo pacman -Rns --noconfirm walker-bin
  sudo pacman -S --noconfirm walker-bin
fi
