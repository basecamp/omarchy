# Configure pacman
sudo cp -f ~/.local/share/omarchy/default/pacman/pacman.conf /etc/pacman.conf
sudo cp -f ~/.local/share/omarchy/default/pacman/mirrorlist /etc/pacman.d/mirrorlist

if lspci -nn | grep -q "106b:180[12]"; then
  echo "Adding T2 MacBook repository to pacman.conf..."
  cat <<EOF | sudo tee -a /etc/pacman.conf >/dev/null

[arch-mact2]
Server = https://mirror.omarchy.org/\$repo/\$arch
SigLevel = Never
EOF
fi
