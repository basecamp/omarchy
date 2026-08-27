echo "Add Kitty open-actions rules for clicking local file links"

# Fresh installs get open-actions.conf from the packaged config directory, so
# only bring existing Kitty installs up to date, and only when they don't
# already have the file — a customized one is never overwritten.
kitty_config="$HOME/.config/kitty/kitty.conf"
open_actions="$HOME/.config/kitty/open-actions.conf"
if [[ -f $kitty_config && ! -e $open_actions && ! -L $open_actions ]]; then
  cp "$OMARCHY_PATH/config/kitty/open-actions.conf" "$open_actions"
fi
