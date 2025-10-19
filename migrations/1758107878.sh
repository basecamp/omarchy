echo "Migrate to Walker 2.0.0"

# Ensure we kill walker even if there's a restarting service running
kill -9 $(pgrep -x walker)

omarchy-pkg-drop walker-bin walker-bin-debug

omarchy-pkg-add elephant \
  elephant-calc \
  elephant-clipboard \
  elephant-bluetooth \
  elephant-desktopapplications \
  elephant-files \
  elephant-menus \
  elephant-providerlist \
  elephant-runner \
  elephant-symbols \
  elephant-unicode \
  elephant-websearch \
  elephant-todo \
  walker

source $OMARCHY_PATH/install/config/walker-elephant.sh

rm -rf ~/.config/walker/themes
omarchy-refresh-walker
