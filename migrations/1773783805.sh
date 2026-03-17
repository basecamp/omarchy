echo "Add sample screenshot hook"

mkdir -p ~/.config/omarchy/hooks

if [[ ! -f ~/.config/omarchy/hooks/screenshot.sample ]]; then
  cp "$OMARCHY_PATH/config/omarchy/hooks/screenshot.sample" ~/.config/omarchy/hooks/screenshot.sample
fi
