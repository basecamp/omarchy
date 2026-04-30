echo "Replace coterie of individual Elephant packages with the single elephant-all package"

if omarchy-pkg-present omarchy-walker; then
  sudo pacman -R --noconfirm omarchy-walker
fi

mapfile -t elephant_packages < <(pacman -Qq | grep '^elephant-' | grep -v '^elephant-all$' || true)

if (( ${#elephant_packages[@]} > 0 )); then
  sudo pacman -Rns --noconfirm "${elephant_packages[@]}"
fi

omarchy-pkg-add elephant-all
omarchy-restart-walker
