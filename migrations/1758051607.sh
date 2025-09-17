echo "Copy configs for ghostty + kitty so they're available as alternative terminal options"

if [[ ! -f ~/.config/ghostty/config ]]; then
  mkdir -p ~/.config/ghostty
  cp -Rpf $OMARCHY_PATH/config/ghostty/config ~/.config/ghostty/config
fi

if [[ ! -f ~/.config/kitty/kitty.conf ]]; then
  mkdir -p ~/.config/kitty
  cp -Rpf $OMARCHY_PATH/config/kitty/kitty.conf ~/.config/kitty/kitty.conf
fi
