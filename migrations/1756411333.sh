echo "Use new Omarchy mirror as default"

echo -e "Server = https://mirror.omarchy.org/\$repo/os/\$arch\nServer = https://mirror.rackspace.com/archlinux/\$repo/os/\$arch\nServer = https://geo.mirror.pkgbuild.com/\$repo/os/\$arch" |
  sudo tee /etc/pacman.d/mirrorlist >/dev/null
