echo "Re-stage the current theme so an extra theme's code is dropped"

# An extra theme could ship hyprland.lua, gum_env.lua, neovim.lua and terminal
# configs, and they were copied straight into the staged theme that Hyprland
# requires at login and the terminals include at launch. Staging drops them now,
# but an install that already applied such a theme keeps the staged copies until
# something changes the theme, which may be never. Re-stage once so the fix
# reaches the themes already in place rather than only the next one chosen.
theme_name_path="$HOME/.local/state/omarchy/current/theme.name"

[[ -s $theme_name_path ]] || exit 0

omarchy-theme-refresh
