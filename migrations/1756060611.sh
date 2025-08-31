echo "Migrate AUR packages to official repos where possible"

reinstall_package_opr() {
  if omarchy-pkg-present $1; then
    sudo pacman -Rns --noconfirm $1
    sudo pacman -S --noconfirm ${2:-$1}
  fi
}

omarchy-pkg-drop yay-bin-debug

reinstall_package_opr yay-bin yay
reinstall_package_opr obsidian-bin obsidian
reinstall_package_opr localsend-bin localsend
reinstall_package_opr omarchy-chromium-bin omarchy-chromium
reinstall_package_opr walker-bin
reinstall_package_opr wl-screenrec
reinstall_package_opr python-terminaltexteffects
reinstall_package_opr tzupdate
reinstall_package_opr typora
reinstall_package_opr ttf-ia-writer
