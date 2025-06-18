BACKGROUNDS_DIR=~/.config/omarchy/backgrounds/catppucin

if [[ ! -d $BACKGROUNDS_DIR ]]; then
  mkdir -p $BACKGROUNDS_DIR
  gum spin --title "Downloading background image..." -- curl -sL -o $BACKGROUNDS_DIR/1-catppuccin.png https://github.com/basecamp/omakub/raw/refs/heads/master/themes/catppuccin/background.png
fi
