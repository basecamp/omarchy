echo "Migrate localsend-bin to localsend package"

if omarchy-pkg-present localsend-bin; then
  omarchy-pkg-drop localsend-bin
  omarchy-pkg-add localsend
fi
