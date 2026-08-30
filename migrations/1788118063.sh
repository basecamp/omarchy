echo "Add YouTube Tile Mode extension to Chromium-based browsers"

YOUTUBE_TILE_EXT="$OMARCHY_PATH/default/chromium/extensions/youtube-tile"

add_youtube_tile_extension() {
  local file=$1

  [[ -f $file ]] || return 0
  grep -q "extensions/youtube-tile" "$file" && return 0

  if grep -q "^--load-extension=" "$file"; then
    sed -i --follow-symlinks "s|^--load-extension=\(.*\)$|--load-extension=\1,$YOUTUBE_TILE_EXT|" "$file"
  else
    [[ -n $(tail -c1 "$file") ]] && echo >>"$file"
    echo "--load-extension=$YOUTUBE_TILE_EXT" >>"$file"
  fi
}

for conf in chromium chrome google-chrome brave brave-beta brave-nightly brave-origin microsoft-edge-stable; do
  add_youtube_tile_extension "$HOME/.config/$conf-flags.conf"
done
