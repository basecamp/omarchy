echo "Rebuild python-terminaltexteffects for Python 3.14 compatibility"

if omarchy-pkg-present python-terminaltexteffects; then
  omarchy-pkg-drop python-terminaltexteffects
  omarchy-pkg-aur-add python-terminaltexteffects
fi
