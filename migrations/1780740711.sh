echo "Add Mako override config"

config_dir="$HOME/.config/omarchy"
theme_dir="$config_dir/current/theme"

mkdir -p "$config_dir" "$theme_dir"

if [ ! -f "$config_dir/mako.ini" ]; then
  cp "$OMARCHY_PATH/config/omarchy/mako.ini" "$config_dir/mako.ini"
fi

if [ ! -f "$theme_dir/mako-theme.ini" ]; then
  cp "$OMARCHY_PATH/default/themed/mako-theme.ini.tpl" "$theme_dir/mako-theme.ini"
fi
