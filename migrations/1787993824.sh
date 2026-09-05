echo "Re-render the current theme so foot reports the right color-theme mode"

# The foot template wrote every palette into [colors-dark], so foot answered the
# CSI ?996n query with "dark" even under a light theme. The generated foot.ini
# is only rewritten when the theme changes, which on an install that already
# settled on a theme may be never, so re-render once to reach it.
staged_foot="$HOME/.local/state/omarchy/current/theme/foot.ini"
theme_name_path="$HOME/.local/state/omarchy/current/theme.name"

[[ -f $staged_foot ]] || exit 0

if grep -q '^initial-color-theme=' "$staged_foot"; then
  exit 0
fi

# omarchy-theme-remove deletes a theme without switching away, so the current
# one may be gone, and omarchy-theme-set exits 1 on a name it cannot find --
# which under the runner's bash -euo pipefail aborts the whole migration run.
[[ -s $theme_name_path ]] || exit 0
theme_name=$(<"$theme_name_path")
[[ -d $OMARCHY_PATH/themes/$theme_name || -d $HOME/.config/omarchy/themes/$theme_name ]] || exit 0

omarchy-theme-refresh
