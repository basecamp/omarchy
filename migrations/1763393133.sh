echo "Link new theme picker config"

mkdir -p ~/.config/elephant/menus
ln -snf $OMARCHY_PATH/default/elephant/omarchy_themes.lua ~/.config/elephant/menus/omarchy_themes.lua
omarchy-restart-walker
