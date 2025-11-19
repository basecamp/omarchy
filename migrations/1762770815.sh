echo "Pull packages from stable Arch mirror"

omarchy-refresh-pacman-mirrorlist stable
sudo pachman -Syu
