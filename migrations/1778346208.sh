echo "Fix fontconfig monospace binding so app-specific fonts are not overridden"

if [[ -f ~/.config/fontconfig/fonts.conf ]] && command -v xmlstarlet >/dev/null 2>&1; then
  xmlstarlet ed -L \
    -u '//match[@target="pattern"][test/string="monospace"]/edit[@name="family"]/@mode' \
    -v "append" \
    -u '//match[@target="pattern"][test/string="monospace"]/edit[@name="family"]/@binding' \
    -v "same" \
    ~/.config/fontconfig/fonts.conf
  fc-cache -f >/dev/null 2>&1
fi
