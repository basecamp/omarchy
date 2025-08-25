echo "Update fastfetch config with new Omarchy logo"

omarchy-refresh-config fastfetch/config.jsonc

mkdir -p ~/.config/omarchy/branding
cp $OMARCHY_PATH/icon.txt ~/.config/omarchy/branding/about.txt
