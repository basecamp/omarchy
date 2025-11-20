echo "Migrate to proper packages for localsend and asdcontrol"

if omarchy-pkg-present localsend-bin; then
  omarchy-pkg-drop localsend-bin
  omarchy-pkg-add localsend
fi

if omarchy-pkg-present asdcontrol-git; then
  omarchy-pkg-drop asdcontrol-git
  omarchy-pkg-add asdcontrol
fi
