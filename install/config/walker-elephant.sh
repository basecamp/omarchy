#!/bin/bash

# Ensure Walker service is started automatically on boot
mkdir -p ~/.config/autostart/
cp $OMARCHY_PATH/default/walker/walker.desktop ~/.config/autostart/

# And is restarted if it crashes or is killed
mkdir -p ~/.config/systemd/user/app-walker@autostart.service.d/
cp $OMARCHY_PATH/default/walker/restart.conf ~/.config/systemd/user/app-walker@autostart.service.d/restart.conf

# Note: On Fedora, walker auto-restart on update requires a DNF post-transaction hook or systemd path unit.
# Skipping pacman hook creation for now.

# Link the visual theme menu config
mkdir -p ~/.config/elephant/menus
ln -snf $OMARCHY_PATH/default/elephant/omarchy_themes.lua ~/.config/elephant/menus/omarchy_themes.lua
ln -snf $OMARCHY_PATH/default/elephant/omarchy_background_selector.lua ~/.config/elephant/menus/omarchy_background_selector.lua
ln -snf $OMARCHY_PATH/default/elephant/omarchy_unlocks.lua ~/.config/elephant/menus/omarchy_unlocks.lua
