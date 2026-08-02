echo "Add WhatsApp Slim extension to existing Brave Origin installations"

WHATSAPP_SLIM_EXT="$OMARCHY_PATH/default/chromium/extensions/whatsapp-slim"

add_whatsapp_slim_extension() {
  local file=$1

  [[ -f $file ]] || return 0
  grep -q "extensions/whatsapp-slim" "$file" && return 0

  if grep -q "^--load-extension=" "$file"; then
    sed -i --follow-symlinks "s|^--load-extension=\(.*\)$|--load-extension=\1,$WHATSAPP_SLIM_EXT|" "$file"
  else
    echo "--load-extension=$WHATSAPP_SLIM_EXT" >>"$file"
  fi
}

# The previous migration (1785543725) mistakenly targeted brave-origin-beta instead of brave-origin.
# This follow-up migration ensures brave-origin is updated for users who already ran the faulty migration.
add_whatsapp_slim_extension "$HOME/.config/brave-origin-flags.conf"
