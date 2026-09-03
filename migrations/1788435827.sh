echo "Apply Omarchy mpv theme (oscc bar follows the active palette)"

mpv_dir="$HOME/.config/mpv"

if [[ ! -f $mpv_dir/scripts/oscc.lua && -f $OMARCHY_PATH/config/mpv/scripts/oscc.lua ]]; then
  mkdir -p "$mpv_dir/scripts"
  cp -f "$OMARCHY_PATH/config/mpv/scripts/oscc.lua" "$mpv_dir/scripts/oscc.lua"
fi

if [[ ! -f $mpv_dir/fonts/oscc.ttf && -f $OMARCHY_PATH/config/mpv/fonts/oscc.ttf ]]; then
  mkdir -p "$mpv_dir/fonts"
  cp -f "$OMARCHY_PATH/config/mpv/fonts/oscc.ttf" "$mpv_dir/fonts/oscc.ttf"
fi

omarchy-theme-set-mpv
