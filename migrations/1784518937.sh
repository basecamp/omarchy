echo "Point the Neovim theme symlink at the Omarchy 3.x theme location"

# omarchy-nvim briefly created ~/.config/nvim/lua/plugins/theme.lua linked to
# the Omarchy 4 theme location, which doesn't exist on Omarchy 3.x, so Neovim
# failed to load plugins.theme on startup (#6309). Retarget the link to the
# 3.x location, but leave any customized link alone.
theme_link="$HOME/.config/nvim/lua/plugins/theme.lua"
if [[ -L $theme_link && $(readlink "$theme_link") == *.local/state/omarchy/current/theme/neovim.lua ]]; then
  ln -snf "../../../../.config/omarchy/current/theme/neovim.lua" "$theme_link"
fi
