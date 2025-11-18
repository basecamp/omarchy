echo "Set power profile to balanced if set to performance"

profile=$(powerprofilesctl get 2>/dev/null || echo -n balanced)
if [[ "$profile" -eq "performance" ]]; then
  powerprofilesctl set balanced
fi
