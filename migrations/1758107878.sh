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

source $OMARCHY_PATH/install/config/walker-elephant.sh

omarchy-refresh-walker
