BACKGROUNDS_DIR=~/.config/omarchy/backgrounds/everforest

if [[ ! -d $BACKGROUNDS_DIR ]]; then
  mkdir -p $BACKGROUNDS_DIR
  gum spin --title "Downloading background image..." -- curl -sL -o $BACKGROUNDS_DIR/1-everforest.jpg https://github.com/basecamp/omakub/raw/refs/heads/master/themes/everforest/background.jpg
fi
