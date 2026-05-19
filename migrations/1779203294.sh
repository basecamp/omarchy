echo "Remove Wiremix audio mixer"

if omarchy-pkg-present wiremix; then
  omarchy-pkg-drop wiremix
fi

rm -rf "$HOME/.config/wiremix"
rm -f "$HOME/.local/share/applications/wiremix.desktop"

if omarchy-cmd-present update-desktop-database; then
  update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
fi
