echo "Install herdr and seed its Omarchy config"

omarchy-mise-install herdr

# Only seed. A user who already has a herdr config keeps it; omarchy-refresh-herdr
# is the explicit way to take the shipped defaults.
[[ -f "$HOME/.config/herdr/config.toml" ]] || omarchy-refresh-config herdr/config.toml
