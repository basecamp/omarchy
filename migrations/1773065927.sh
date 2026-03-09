echo "Move Zed theme switching into Omarchy and remove legacy omazed integration"

if omarchy-pkg-present omazed; then
  omarchy-pkg-drop omazed

  # Remove the omazed hook from theme-set
  sed -i '/# >>> omazed hook - do not edit >>>/,/# <<< omazed hook - do not edit <<</d' "$HOME/.config/omarchy/hooks/theme-set"

  rm -rf "$HOME/.local/share/omazed"
  rm -f "$HOME/.config/zed/themes/omazed.json"
fi

"$OMARCHY_PATH/bin/omarchy-theme-set-zed"
