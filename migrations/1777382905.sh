echo "Use interactive unlock (Plymouth) selector menu"

mkdir -p ~/.config/elephant/menus
ln -snf $OMARCHY_PATH/default/elephant/omarchy_unlocks.lua ~/.config/elephant/menus/omarchy_unlocks.lua
omarchy-restart-walker
