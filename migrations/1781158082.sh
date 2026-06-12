echo "Relink Neovim theme to Omarchy current state"

theme_link="$HOME/.config/nvim/lua/plugins/theme.lua"
legacy_absolute_target="$HOME/.config/omarchy/current/theme/neovim.lua"
legacy_relative_target="../../../omarchy/current/theme/neovim.lua"
legacy_home_target="~/.config/omarchy/current/theme/neovim.lua"
current_relative_target="../../../../.local/state/omarchy/current/theme/neovim.lua"

[[ -L $theme_link ]] || exit 0

target=$(readlink "$theme_link") || exit 0

case "$target" in
  "$legacy_absolute_target"|"$legacy_relative_target"|"$legacy_home_target")
    ln -sfn "$current_relative_target" "$theme_link"
    ;;
esac
