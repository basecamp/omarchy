echo "Migrate to Walker 1.0.0-Beta"

pkill walker || true

omarchy-pkg-drop walker-bin walker-bin-debug

omarchy-pkg-add elephant \
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

install -D -m 644 $OMARCHY_PATH/default/systemd/user/elephant.service ~/.config/systemd/user/elephant.service

systemctl enable --now --user elephant.service
omarchy-restart-walker
