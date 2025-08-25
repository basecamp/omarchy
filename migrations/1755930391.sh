echo "Migrate to Walker 1.0.0-Beta"

pkill walker || true

yay -Rns --noconfirm walker-bin walker-bin-debug

yay -Sy --noconfirm --needed \
  elephant \
  elephant-archlinuxpkgs \
  elephant-calc \
  elephant-clipboard \
  elephant-desktopapplications \
  elephant-files \
  elephant-menus \
  elephant-providerlist \
  elephant-runner \
  elephant-symbols \
  elephant-websearch \
  walker

rm -rf ~/.config/walker
mkdir -p ~/.config/walker
mkdir -p ~/.config/elephant

cp -r ~/.local/share/omarchy/config/walker/* ~/.config/walker/
cp -r ~/.local/share/omarchy/config/elephant/* ~/.config/elephant/

omarchy-refresh-walker
omarchy-refresh-elephant
