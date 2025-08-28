echo "Move Omarchy Package Repository after Arch core/extra/multilib for extra security on resolution"

sudo cp /etc/pacman.conf /etc/pacman.conf.bak
sudo sed -i '/\[omarchy\]/,+2 d' /etc/pacman.conf
sudo sed -i '/\[chaotic-aur\]/i\[omarchy]\nSigLevel = Optional TrustAll\nServer = https://pkgs.omarchy.org/$arch/\n' /etc/pacman.conf ||
  sudo bash -c 'echo -e "\n[omarchy]\nSigLevel = Optional TrustAll\nServer = https://pkgs.omarchy.org/$arch/" >> /etc/pacman.conf'
