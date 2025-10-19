# Handles changes since 3.1.0-RC

echo "Add shift+insert for kitty"
# Add shift+insert paste keybinding to kitty.conf if it doesn't exist
KITTY_CONF="$HOME/.config/kitty/kitty.conf"

if ! grep -q "map shift+insert paste_from_clipboard" "$KITTY_CONF"; then
  sed -i '/map ctrl+insert copy_to_clipboard/a map shift+insert paste_from_clipboard' "$KITTY_CONF"
fi

echo "Update Walker configs"
omarchy-refresh-walker

echo "Copy hooks examples"
cp -r $OMARCHY_PATH/config/omarchy/* $HOME/.config/omarchy/

echo "Add packages for updated omarchy-cmd-screenshot"
omarchy-pkg-add grim slurp wayfreeze-git

echo "Add nfs support by default to Nautilus"
omarchy-pkg-add gvfs-nfs

if [ ! -d "$HOME/.config/nvim" ]; then
  echo "Add missing nvim config"
  omarchy-nvim-setup
fi
