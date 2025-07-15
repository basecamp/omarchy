sudo pacman -S --needed --noconfirm base-devel

if ! command -v yay &>/dev/null; then
  cd /tmp
  git clone https://aur.archlinux.org/yay-bin.git
  cd yay-bin
  makepkg -si --noconfirm
  cd -
  rm -rf yay-bin
  cd ~
fi

# FIXME: Temporary fix for the fact that some locations can't reach the default keyserver
if [[ ! -f "$HOME/.gnupg/gpg.conf" ]]; then
  mkdir -p ~/.gnupg
  echo "keyserver hkps://pgp.mit.edu" >~/.gnupg/dirmngr.conf
fi
