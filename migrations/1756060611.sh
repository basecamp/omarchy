echo "Migrate AUR packages to official repos where possible"

reinstall_package_opr() {
  if pacman -Q $1 >/dev/null; then
    sudo pacman -Rns --noconfirm $1
    sudo pacman -S --noconfirm $1
  fi
}

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

reinstall_package_opr walker-bin
reinstall_package_opr wl-screenrec
reinstall_package_opr python-terminaltexteffects
reinstall_package_opr tzupdate
reinstall_package_opr typora
reinstall_package_opr ttf-ia-writer
