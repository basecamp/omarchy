echo "Migrate to correct packages for localsend and wayfreeze"

if omarchy-pkg-present localsend-bin; then
  omarchy-pkg-drop localsend-bin
  omarchy-pkg-add localsend
fi

if omarchy-pkg-present wayfreeze-git; then
  omarchy-pkg-drop wayfreeze-git
  omarchy-pkg-add wayfreeze
fi
