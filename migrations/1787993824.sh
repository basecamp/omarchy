echo "Re-render the current theme so foot reports the right color-theme mode"

# The foot template wrote every palette into [colors-dark], so foot answered the
# CSI ?996n query with "dark" even under a light theme. The generated foot.ini
# is only rewritten when the theme changes, which on an install that already
# settled on a theme may be never, so re-render once to reach it.
staged_foot="$HOME/.local/state/omarchy/current/theme/foot.ini"

[[ -f $staged_foot ]] || exit 0

if grep -q '^initial-color-theme=' "$staged_foot"; then
  exit 0
fi

omarchy-theme-refresh
