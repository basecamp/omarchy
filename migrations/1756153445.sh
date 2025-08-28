echo "Checking and correcting Snapper configs if needed"
if command -v snapper &>/dev/null; then
  if ! sudo snapper list-configs 2>/dev/null | grep -q "root"; then
    sudo snapper -c root create-config /
  fi

  if ! sudo snapper list-configs 2>/dev/null | grep -q "home"; then
    sudo snapper -c home create-config /home
  fi
fi
