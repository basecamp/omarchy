echo "Fix Super+C copy in neovim by letting Ctrl+Insert pass through to the terminal app"

# Remove ctrl+insert copy binding from Kitty (let the key pass through to neovim)
if [[ -f ~/.config/kitty/kitty.conf ]]; then
  sed -i '/map ctrl+insert copy_to_clipboard/d' ~/.config/kitty/kitty.conf
fi

# Unbind ghostty's ctrl+insert (has a built-in default, so deleting the line isn't enough)
if [[ -f ~/.config/ghostty/config ]]; then
  sed -i 's/control+insert=.*copy_to_clipboard/control+insert=unbind/' ~/.config/ghostty/config
fi

# Remove ctrl+insert copy binding from Alacritty
if [[ -f ~/.config/alacritty/alacritty.toml ]]; then
  sed -i '/mods = "Control", action = "Copy"/d' ~/.config/alacritty/alacritty.toml
fi

# Add neovim keymap so Ctrl+Insert (sent by Hyprland for Super+C) copies visual selection to system clipboard
if [[ -f ~/.config/nvim/lua/config/keymaps.lua ]]; then
  if ! grep -q 'C-Insert' ~/.config/nvim/lua/config/keymaps.lua; then
    cat >> ~/.config/nvim/lua/config/keymaps.lua << 'EOF'

-- Copy visual selection to system clipboard with Ctrl+Insert (triggered by Super+C via Hyprland)
vim.keymap.set("v", "<C-Insert>", '"+y', { desc = "Copy to system clipboard" })
EOF
  fi
fi
