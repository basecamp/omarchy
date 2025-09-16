# Configure pacman
sudo cp -f ~/.local/share/omarchy/default/pacman/pacman.conf /etc/pacman.conf
sudo cp -f ~/.local/share/omarchy/default/pacman/mirrorlist /etc/pacman.d/mirrorlist

if lspci -nn | grep -q "106b:180[12]"; then
  cat <<EOF | sudo tee -a /etc/pacman.conf >/dev/null

[arch-mact2]
Server = https://github.com/NoaHimesaka1873/arch-mact2-mirror/releases/download/release
SigLevel = Never
EOF
fi
