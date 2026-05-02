echo "Replace coterie of individual Elephant packages with the single elephant-all package"

if omarchy-pkg-present omarchy-walker; then
  # Install elephant-all first so the meta-package's deps stay satisfied during removal.
  # elephant-all's Conflicts/Provides cleanly supplants any individual elephant-* subpackages.
  omarchy-pkg-add walker elephant-all

  # Remove only the meta-package itself. No -s so walker (and the elephant deps now
  # provided by elephant-all) stay installed, leaving user walker/elephant configs untouched.
  sudo pacman -R --noconfirm omarchy-walker
fi
