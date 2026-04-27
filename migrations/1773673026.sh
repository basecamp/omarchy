echo "Add flat menu search and Ctrl+J/K navigation to Walker"

# Symlink the new elephant menu module
mkdir -p ~/.config/elephant/menus
ln -snf $OMARCHY_PATH/default/elephant/omarchy_menu_search.lua ~/.config/elephant/menus/omarchy_menu_search.lua

# Add Ctrl+J/K keybinds to walker config if not already present
if ! grep -q "ctrl j" ~/.config/walker/config.toml 2>/dev/null; then
  sed -i 's/^quick_activate = \[\]/quick_activate = []\nnext = ["Down", "ctrl j"]\nprevious = ["Up", "ctrl k"]/' ~/.config/walker/config.toml
fi

# Add < prefix for flat menu search if not already present
if ! grep -q "omarchymenusearch" ~/.config/walker/config.toml 2>/dev/null; then
  sed -i 's/^\[\[emergencies\]\]/[[providers.prefixes]]\nprefix = "<"\nprovider = "menus:omarchymenusearch"\n\n[[emergencies]]/' ~/.config/walker/config.toml
fi

omarchy-restart-walker
