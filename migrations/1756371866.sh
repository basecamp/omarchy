echo "Reload notifications"
cp ~/.local/share/omarchy/default/mako/core.ini ~/.config/mako/
pkill mako || makoctl reload
