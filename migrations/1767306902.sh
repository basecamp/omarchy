echo "Migrate to new theme setup"

omarchy-pkg-add yq

# Move user-added backgrounds from Omarchy theme folders to user config
OMARCHY_DIR="$HOME/.local/share/omarchy"
USER_BACKGROUNDS_DIR="$HOME/.config/omarchy/backgrounds"

if [[ -d "$OMARCHY_DIR/themes" ]]; then
  cd "$OMARCHY_DIR"

  # Get list of git-tracked background files (relative to omarchy dir)
  mapfile -t TRACKED_BACKGROUNDS < <(git ls-files --cached 'themes/*/backgrounds/*' 2>/dev/null)

  # Find all background files and check if they're untracked (user-added)
  for theme_dir in themes/*/; do
    theme_name=$(basename "$theme_dir")
    backgrounds_dir="themes/$theme_name/backgrounds"

    [[ -d "$backgrounds_dir" ]] || continue

    for bg_file in "$backgrounds_dir"/*; do
      [[ -f "$bg_file" ]] || continue

      # Check if this file is tracked by git
      is_tracked=false
      for tracked in "${TRACKED_BACKGROUNDS[@]}"; do
        if [[ "$tracked" == "$bg_file" ]]; then
          is_tracked=true
          break
        fi
      done

      if [[ "$is_tracked" == "false" ]]; then
        # This is a user-added background, move it to user config
        user_theme_bg_dir="$USER_BACKGROUNDS_DIR/$theme_name"
        mkdir -p "$user_theme_bg_dir"
        mv "$bg_file" "$user_theme_bg_dir/"
        echo "Moved user background: $bg_file -> $user_theme_bg_dir/"
      fi
    done
  done
fi

THEMES_DIR="$HOME/.config/omarchy/themes"
CURRENT_THEME_LINK="$HOME/.config/omarchy/current/theme"

# Get current theme name before removing anything
CURRENT_THEME_NAME=""
if [[ -L $CURRENT_THEME_LINK ]]; then
  CURRENT_THEME_NAME=$(basename "$(readlink "$CURRENT_THEME_LINK")")
elif [[ -d $CURRENT_THEME_LINK ]]; then
  CURRENT_THEME_NAME=$(basename "$CURRENT_THEME_LINK")
elif [[ -f "$HOME/.config/omarchy/current/theme.name" ]]; then
  CURRENT_THEME_NAME=$(cat "$HOME/.config/omarchy/current/theme.name")
fi

# Remove all symlinks from ~/.config/omarchy/themes
find "$THEMES_DIR" -mindepth 1 -maxdepth 1 -type l -delete

# Re-apply the current theme with the new system
if [[ -n $CURRENT_THEME_NAME ]]; then
  omarchy-theme-set "$CURRENT_THEME_NAME"
else
  # Backup to ensure a theme is set if we can't deduce the name
  omarchy-theme-set "Tokyo Night"
fi
