# Set mirror to single geo setup
echo 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' |
  sudo tee /etc/pacman.d/mirrorlist >/dev/null

# Update indexes if online
if ping -c5 omarchy.org &>/dev/null; then
  sudo pacman -Syy
fi
