echo "Use verbose package lists for pacman"

sudo sed -i '/^ILoveCandy$/a VerbosePkgLists' /etc/pacman.conf
