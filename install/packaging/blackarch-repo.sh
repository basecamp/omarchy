# Add BlackArch repository if not already configured
if ! grep -q "\[blackarch\]" /etc/pacman.conf 2>/dev/null; then
  echo "Adding BlackArch repository..."
  curl -O https://blackarch.org/strap.sh
  chmod +x strap.sh
  sudo ./strap.sh
  rm -f strap.sh
fi

sudo pacman -Sy --noconfirm
