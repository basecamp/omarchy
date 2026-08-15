echo "Add sample low battery notification hook"

mkdir -p ~/.config/omarchy/hooks/battery-low.d

if [[ ! -f ~/.config/omarchy/hooks/battery-low.d/play-warning-sound.sample ]]; then
  cp "$OMARCHY_PATH/config/omarchy/hooks/battery-low.d/play-warning-sound.sample" ~/.config/omarchy/hooks/battery-low.d/play-warning-sound.sample
fi
