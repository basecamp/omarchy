echo "Add sample post-boot hook"

mkdir -p ~/.config/omarchy/hooks/post-boot.d

if [[ ! -f ~/.config/omarchy/hooks/post-boot.d/weather.sample ]]; then
  cp "$OMARCHY_PATH/config/omarchy/hooks/post-boot.d/weather.sample" ~/.config/omarchy/hooks/post-boot.d/weather.sample
fi
