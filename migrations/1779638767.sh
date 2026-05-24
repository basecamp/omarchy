
echo "Install ghostty-nautilus for the 'Open in Ghostty' Nautilus right-click extension"

if omarchy-pkg-present ghostty && omarchy-pkg-missing ghostty-nautilus; then
  omarchy-pkg-add ghostty-nautilus
fi
