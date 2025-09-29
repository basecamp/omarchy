#  FIXME: (2025-09-23) Jon => why are we configuring pacman again? Already did
#  it in preflight/pacman.sh
#
# Configure pacman
if [ -n "$OMARCHY_ARM" ]; then
  sudo cp -f ~/.local/share/omarchy/default/pacman/pacman.conf.arm /etc/pacman.conf
  sudo cp -f ~/.local/share/omarchy/default/pacman/mirrorlist.arm /etc/pacman.d/mirrorlist
  sudo cp -f ~/.local/share/omarchy/default/pacman/mirrorlist.asahi-alarm /etc/pacman.d/mirrorlist.asahi-alarm
else
  sudo cp -f ~/.local/share/omarchy/default/pacman/pacman.conf /etc/pacman.conf
  sudo cp -f ~/.local/share/omarchy/default/pacman/mirrorlist-stable /etc/pacman.d/mirrorlist

  if lspci -nn | grep -q "106b:180[12]"; then
    cat <<EOF | sudo tee -a /etc/pacman.conf >/dev/null

  [arch-mact2]
  Server = https://github.com/NoaHimesaka1873/arch-mact2-mirror/releases/download/release
  SigLevel = Never
  EOF
    fi
fi
