echo "Drop elephant-files"

if omarchy-pkg-present elephant-files; then
  omarchy-pkg-drop elephant-files
fi
