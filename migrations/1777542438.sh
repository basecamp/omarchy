echo "Replace coterie of individual Elephant packages with the single elephant-all package"

if omarchy-pkg-present omarchy-walker; then
  omarchy-pkg-drop omarchy-walker
  omarchy-pkg-add walker elephant-all
  omarchy-restart-walker
fi
