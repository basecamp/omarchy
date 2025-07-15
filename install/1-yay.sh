sudo pacman -S --needed --noconfirm base-devel

if ! command -v yay &>/dev/null; then
  cd /tmp
  git clone https://aur.archlinux.org/yay-bin.git
  cd yay-bin
  makepkg -si --noconfirm
  cd -
  rm -rf yay-bin
  cd ~

  # Add fun and color to the pacman installer
  sed -i '/^\[options\]/a Color\nILoveCandy' /etc/pacman.conf
fi
