BACKGROUNDS_DIR=~/.config/omarchy/backgrounds/nord

if [[ ! -d $BACKGROUNDS_DIR ]]; then
  mkdir -p $BACKGROUNDS_DIR
  gum spin --title "Downloading background image..." -- curl -sL -o $BACKGROUNDS_DIR/1-nord.png https://github.com/basecamp/omakub/raw/refs/heads/master/themes/nord/background.png
fi
