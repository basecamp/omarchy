echo "Use Inter as default UI font"

omarchy-pkg-add inter-font

fontconfig="$HOME/.config/fontconfig/fonts.conf"

if [ -f "$fontconfig" ] && ! grep -q '>Inter<' "$fontconfig"; then
  sed -i \
    -e '/<string>Liberation Sans<\/string>/i\      <string>Inter</string>' \
    -e '/<family>Liberation Sans<\/family>/i\      <family>Inter</family>' \
    "$fontconfig"
fi
