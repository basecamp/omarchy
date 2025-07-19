echo "Replace wofi with walker as the default launcher"
yay -S --noconfirm --needed walker-bin libqalculate
yay -Rns --noconfirm wofi

if gum confirm "Launcher changed to walker. Would you like to remove the wofi config files?"; then
  rm -rf ~/.config/wofi
fi

mkdir -p ~/.config/walker
cp -r ~/.local/share/omarchy/config/walker/* ~/.config/walker/
