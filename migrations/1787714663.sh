echo "Generate and activate the Oh My Pi theme for the current Omarchy theme"

theme_state="$HOME/.local/state/omarchy/current"

[[ -s $theme_state/theme.name ]] || exit 0

theme_name=$(<"$theme_state/theme.name")

# A staged theme is only re-rendered when the theme changes, so an install that
# keeps the theme it already has would never generate the new omp.json.
if [[ ! -f $theme_state/theme/omp.json ]]; then
  if [[ -d $OMARCHY_PATH/themes/$theme_name || -d $HOME/.config/omarchy/themes/$theme_name ]]; then
    omarchy-theme-refresh
  else
    # A theme removed while it was current leaves theme.name naming it with
    # nothing left to re-stage from, and omarchy-theme-set refuses a name it
    # cannot find. Seed the default instead, the way migration 1787481315 does,
    # so this migration records itself rather than failing every run and
    # blocking the ones behind it.
    echo "Theme '$theme_name' no longer exists; applying the default instead"
    omarchy-theme-set "Tokyo Night"
  fi
fi

# Choosing Oh My Pi as the default agent is what points its config at the
# generated theme, and for anyone already using it that choice is long past.
# A theme that carries no palette at all stages no omp.json, and activation
# refuses to run without one, so it is asked for only when there is something
# to activate.
if [[ -f $theme_state/theme/omp.json && $(omarchy-default-agent) == "omp" ]]; then
  omarchy-theme-set-omp --activate
fi

exit 0
