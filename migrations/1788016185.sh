echo "Seed the Herdr profile for the Omarchy scratchpad agent"

# Only seed. A user who already has this profile keeps their customization.
[[ -f "$HOME/.config/herdr/scratchpad.toml" ]] ||
  omarchy-refresh-config herdr/scratchpad.toml
