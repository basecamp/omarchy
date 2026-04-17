echo "Install ghostty-nautilus for Ghostty users"

if omarchy-pkg-present ghostty; then
  omarchy-pkg-add ghostty-nautilus
fi
