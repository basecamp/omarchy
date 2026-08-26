echo "Generate and activate the Oh My Pi theme for the current Omarchy theme"

theme_state="$HOME/.local/state/omarchy/current"

[[ -s $theme_state/theme.name ]] || exit 0

# A staged theme is only re-rendered when the theme changes, so an install that
# keeps the theme it already has would never generate the new omp.json.
[[ -f $theme_state/theme/omp.json ]] || omarchy-theme-refresh

# Choosing Oh My Pi as the default agent is what points its config at the
# generated theme, and for anyone already using it that choice is long past.
[[ $(omarchy-default-agent) == "omp" ]] && omarchy-theme-set-omp --activate

exit 0
