echo "Add new menu elephant plugins and update walker config"

WALKER_CONFIG=~/.config/walker/config.toml

# Link new elephant menu plugins
mkdir -p ~/.config/elephant/menus
ln -snf $OMARCHY_PATH/default/elephant/omarchy_main_menu.lua ~/.config/elephant/menus/omarchy_main_menu.lua
ln -snf $OMARCHY_PATH/default/elephant/omarchy_menu.lua ~/.config/elephant/menus/omarchy_menu.lua

# Update walker config to use new menu providers
if [[ -f "$WALKER_CONFIG" ]]; then
  # Add menu providers to default array if not present
  if ! grep -q "menus:omarchymenu_main" "$WALKER_CONFIG"; then
    sed -i '/^default = \[$/,/^\]$/ {
      /^default = \[$/a\  "menus:omarchymenu_main",\n  "menus:omarchymenu_global",
    }' "$WALKER_CONFIG"
  fi

  # Add empty provider setting if not present
  if ! grep -q "^empty = " "$WALKER_CONFIG"; then
    sed -i '/^]$/,/^\[\[providers\.prefixes\]\]/ {
      /^]$/ {
        N
        /\n\[\[providers\.prefixes\]\]/i empty = ["menus:omarchymenu_main"]
      }
    }' "$WALKER_CONFIG"
  fi

  # Add vim-style keybinds if not present
  if ! grep -q 'next = ' "$WALKER_CONFIG"; then
    sed -i '/^quick_activate = /a next = ["Down", "ctrl j"]\nprevious = ["Up", "ctrl k"]' "$WALKER_CONFIG"
  fi

  # Update symbols column width
  sed -i 's/^symbols = 1/symbols = 3/' "$WALKER_CONFIG"
fi

omarchy-restart-walker
