# Configure pacman
sudo cp -f ~/.local/share/omarchy/default/pacman/pacman.conf /etc/pacman.conf

# Support for China mirrors - users can set OMARCHY_USE_CHINA_MIRRORS=1
if [[ "${OMARCHY_USE_CHINA_MIRRORS:-0}" == "1" ]]; then
  echo "Using China mirrors for better connectivity in mainland China..."
  sudo cp -f ~/.local/share/omarchy/default/pacman/mirrorlist-china /etc/pacman.d/mirrorlist
else
  sudo cp -f ~/.local/share/omarchy/default/pacman/mirrorlist-stable /etc/pacman.d/mirrorlist
fi

if lspci -nn | grep -q "106b:180[12]"; then
  cat <<EOF | sudo tee -a /etc/pacman.conf >/dev/null

[arch-mact2]
Server = https://github.com/NoaHimesaka1873/arch-mact2-mirror/releases/download/release
SigLevel = Never
EOF
fi
