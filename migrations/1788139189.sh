echo "Refresh the current theme if its selection color is invisible against the foreground"

# omarchy-theme-colors-from-alacritty used to fall back to foreground for
# selection when a theme's alacritty.toml had no [colors.selection], leaving
# Neovim's Visual highlight, gum prompts, and btop's selected row invisible.
# A theme active from before that fix keeps the stale value baked into its
# materialized colors.toml until something regenerates it. No authored theme
# sets selection equal to foreground on purpose -- that pairing is exactly
# what made the highlight invisible -- so refreshing on this fingerprint is
# safe for every theme, and a no-op for one whose colors.toml was hand-authored
# straight through without regeneration.

current_colors="$HOME/.local/state/omarchy/current/theme/colors.toml"

[[ -f $current_colors ]] || exit 0

selection=$(awk -F'"' '/^selection = /{print $2; exit}' "$current_colors")
foreground=$(awk -F'"' '/^foreground = /{print $2; exit}' "$current_colors")

[[ -n $selection && $selection == "$foreground" ]] || exit 0

omarchy-theme-refresh
