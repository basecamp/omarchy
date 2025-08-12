echo "Add auto-loading files for neovim..."

cp -R ~/.local/share/omarchy/config/nvim/* ~/.config/nvim/
if ! grep -q 'require("omarchy.theme_reload").setup()' ~/.config/nvim/init.lua; then
  cat <<EOF >>~/.config/nvim/init.lua

-- Setup theme reloader
require("omarchy.theme_reload").setup()
EOF
fi

if [[ -d ~/.config/omarchy/themes/catppuccin ]]; then
  echo "Update Catppuccin neovim theme files"
  cp ~/.local/share/omarchy/themes/catppuccin/neovim.lua ~/.config/omarchy/themes/catppuccin/
fi

if [[ -d ~/.config/omarchy/themes/osaka-jade ]]; then
  echo "Update Osaka Jade neovim theme files"
  cp ~/.local/share/omarchy/themes/osaka-jade/neovim.lua ~/.config/omarchy/themes/osaka-jade/
fi