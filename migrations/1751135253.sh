if ! command -v bat &>/dev/null; then
  # Add missing installation of bat
  echo "Add missing installation of bat (used by the ff alias)"
  sudo dnf install -y bat
fi
