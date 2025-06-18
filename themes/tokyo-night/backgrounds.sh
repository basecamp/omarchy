BACKGROUNDS_DIR=~/.config/omarchy/backgrounds/tokyo-night

if [[ -z $BACKGROUNDS_DIR ]]; then
  mkdir -p $BACKGROUNDS_DIR
  gum spin --title "Downloading background image..." -- curl -sL -o $BACKGROUNDS_DIR/1-Milad-Fakurian-Abstract-Purple-Blue.jpg https://images.unsplash.com/photo-1620207418302-439b387441b0
  gum spin --title "Downloading background image..." -- curl -sL -o $BACKGROUNDS_DIR/2-Pawel-Czerwinski-Abstract-Purple-Blue.jpg https://images.unsplash.com/photo-1651870364199-fc5f9f46ac85
  gum spin --title "Downloading background image..." -- curl -sL -o $BACKGROUNDS_DIR/3-Jr-Korpa-Abstract-Purple-Blue.jpg https://images.unsplash.com/flagged/photo-1567400358593-9e6382752ea2
fi
