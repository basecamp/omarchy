echo "Switch to the Omarchy quickshell-git build so shell restarts wait for instance exit"

if ! omarchy-pkg-present quickshell-git; then
  # One transaction with --ask 4 so pacman accepts replacing the conflicting
  # quickshell package in place; packages depending on quickshell stay
  # satisfied through the provides.
  sudo pacman -S --noconfirm --ask 4 quickshell-git
  omarchy-state set restart-shell-required
fi
