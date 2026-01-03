echo "Migrate to new theme setup"

omarchy-pkg-add yq

THEMES_DIR="$HOME/.config/omarchy/themes"
CURRENT_THEME_LINK="$HOME/.config/omarchy/current/theme"

# Get current theme name from symlink before removing anything
CURRENT_THEME_NAME=""
if [[ -L $CURRENT_THEME_LINK ]]; then
  CURRENT_THEME_NAME=$(basename "$(readlink "$CURRENT_THEME_LINK")")
elif [[ -f "$HOME/.config/omarchy/current/theme.name" ]]; then
  CURRENT_THEME_NAME=$(cat "$HOME/.config/omarchy/current/theme.name")
fi

# Remove all symlinks from ~/.config/omarchy/themes
find "$THEMES_DIR" -mindepth 1 -maxdepth 1 -type l -delete

# Re-apply the current theme with the new system
if [[ -n $CURRENT_THEME_NAME ]]; then
  omarchy-theme-set "$CURRENT_THEME_NAME"
fi
