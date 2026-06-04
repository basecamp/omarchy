echo "Add yt-dlp download extension (Alt+Shift+D) to Chromium-based browsers"

YTDLP_EXT="$OMARCHY_PATH/default/chromium/extensions/yt-dlp"

add_ytdlp_extension() {
  local file=$1

  [[ -f $file ]] || return 0
  grep -q "extensions/yt-dlp" "$file" && return 0

  if grep -q "^--load-extension=" "$file"; then
    sed -i --follow-symlinks "s|^--load-extension=\(.*\)$|--load-extension=\1,$YTDLP_EXT|" "$file"
  else
    echo "--load-extension=$YTDLP_EXT" >>"$file"
  fi
}

for conf in chromium chrome google-chrome brave brave-beta brave-nightly brave-origin-beta microsoft-edge-stable; do
  add_ytdlp_extension "$HOME/.config/$conf-flags.conf"
done

omarchy-pkg-add yt-dlp

# Register the native messaging host that runs yt-dlp for the extension.
omarchy-install-chromium-ytdlp || true
