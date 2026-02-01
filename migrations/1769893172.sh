echo "Unmask sleep.target so suspend works"

if systemctl show -p LoadState sleep.target 2>/dev/null | grep -q "LoadState=masked"; then
  sudo systemctl unmask sleep.target
fi
