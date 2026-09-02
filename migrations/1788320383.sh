echo "Park a single window on the left or right half instead of a centered square"

flag="$HOME/.local/state/omarchy/toggles/hypr/single-window-aspect-ratio.lua"
source="$OMARCHY_PATH/default/hypr/toggles/single-window-aspect-ratio.lua"

[[ -f $flag && -f $source ]] || exit 0
grep -q 'single_window_aspect_ratio' "$flag" || exit 0

cp "$source" "$flag"
hyprctl reload >/dev/null 2>&1 || true
