echo "Add custom battery charging profile config"

mkdir -p ~/.config/omarchy/system

if [[ ! -f ~/.config/omarchy/system/battery-profile.conf ]]; then
  cp "$OMARCHY_PATH/config/omarchy/system/battery-profile.conf" ~/.config/omarchy/system/battery-profile.conf
fi
