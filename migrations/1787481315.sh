echo "Re-stage the current theme so an installed theme's code is dropped"

# A theme installed from a repo could ship hyprland.lua, gum_env.lua, neovim.lua
# and terminal configs, and they were copied straight into the staged theme that
# Hyprland requires at login and the terminals include at launch. Staging drops
# them now, but an install that already applied such a theme keeps the staged
# copies until something changes the theme, which may be never. Re-stage once so
# the fix reaches the themes already in place rather than only the next one.
theme_name_path="$HOME/.local/state/omarchy/current/theme.name"

[[ -s $theme_name_path ]] || exit 0

theme_name=$(<"$theme_name_path")

# A theme removed while it was still current leaves theme.name naming it and the
# staged copy behind, so there is nothing left to re-stage from and those staged
# files are exactly the ones this is here to drop. Seed the default instead,
# which is where a fresh install starts and what the removal should have left.
if [[ ! -d $OMARCHY_PATH/themes/$theme_name && ! -d $HOME/.config/omarchy/themes/$theme_name ]]; then
  echo "Theme '$theme_name' no longer exists; applying the default instead"
  omarchy-theme-set "Tokyo Night"
  exit 0
fi

omarchy-theme-refresh
