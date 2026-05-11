echo "Add Omarchy theme marketplace to Walker"

mkdir -p ~/.config/elephant/menus
ln -snf "$OMARCHY_PATH/default/elephant/omarchy_theme_marketplace.lua" ~/.config/elephant/menus/omarchy_theme_marketplace.lua
omarchy-restart-walker
