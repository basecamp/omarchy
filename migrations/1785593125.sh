echo "Add the WhatsApp Omarchy Theme extension and register its native messaging host"

WHATSAPP_THEME_EXT="$OMARCHY_PATH/default/chromium/extensions/whatsapp-theme"

add_whatsapp_theme_extension() {
  local file=$1

  [[ -f $file ]] || return 0
  grep -q "extensions/whatsapp-theme" "$file" && return 0

  if grep -q "^--load-extension=" "$file"; then
    sed -i --follow-symlinks "s|^--load-extension=\(.*\)$|--load-extension=\1,$WHATSAPP_THEME_EXT|" "$file"
  else
    echo "--load-extension=$WHATSAPP_THEME_EXT" >>"$file"
  fi
}

for conf in chromium chrome google-chrome brave brave-beta brave-nightly brave-origin-beta microsoft-edge-stable; do
  add_whatsapp_theme_extension "$HOME/.config/$conf-flags.conf"
done

# The extension follows the theme over native messaging (com.omarchy.theme), so
# register its host manifest in every Chromium profile root.
omarchy-install-chromium-theme
