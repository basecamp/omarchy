echo "Re-stage Tokyo Night with packaged boot intro videos"

theme_name_path="$HOME/.local/state/omarchy/current/theme.name"

[[ -s $theme_name_path ]] || exit 0

theme_name=$(<"$theme_name_path")
[[ $theme_name == "tokyo-night" ]] || exit 0

omarchy-theme-refresh
