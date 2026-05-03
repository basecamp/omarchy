echo "Add sample low battery notification hook"

mkdir -p ~/.config/omarchy/hooks

if [[ ! -f ~/.config/omarchy/hooks/battery-low.sample ]]; then
  cp "$OMARCHY_PATH/config/omarchy/hooks/battery-low.sample" ~/.config/omarchy/hooks/battery-low.sample
fi
