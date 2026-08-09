echo "Add WhatsApp Slim extension to Chromium-based browsers"

WHATSAPP_SLIM_EXT="$OMARCHY_PATH/default/chromium/extensions/whatsapp-slim"

add_whatsapp_slim_extension() {
  local file=$1

  [[ -f $file ]] || return 0
  grep -q "extensions/whatsapp-slim" "$file" && return 0

  if grep -q "^--load-extension=" "$file"; then
    sed -i --follow-symlinks "s|^--load-extension=\(.*\)$|--load-extension=\1,$WHATSAPP_SLIM_EXT|" "$file"
  else
    [[ -n $(tail -c1 "$file") ]] && echo >>"$file"
    echo "--load-extension=$WHATSAPP_SLIM_EXT" >>"$file"
  fi
}

for conf in chromium chrome google-chrome brave brave-beta brave-nightly brave-origin microsoft-edge-stable; do
  add_whatsapp_slim_extension "$HOME/.config/$conf-flags.conf"
done
