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
#
# omarchy-theme-set used to recopy a baked-in source colors.toml as-is, so
# refresh alone did not repair an extra/git theme that committed the old
# fingerprint. It now rewrites selection to color8 (bright black, falling
# back to normal black) on the staged copy when that fingerprint is present,
# before templates are generated from the repaired palette. The source
# colors.toml itself -- which may be a git clone or a symlink into the
# user's own dotfiles -- is left untouched, so this repair repeats on every
# switch of an affected theme, harmlessly.

theme_name_path="$HOME/.local/state/omarchy/current/theme.name"

[[ -s $theme_name_path ]] || exit 0

theme_name=$(<"$theme_name_path")

# A theme removed while it was still current leaves theme.name naming it and the
# staged copy behind, so omarchy-theme-refresh would exit 1 ("Theme does not
# exist") and stall every later migration. Seed the default instead, which is
# where a fresh install starts and what the removal should have left.
if [[ ! -d $OMARCHY_PATH/themes/$theme_name && ! -d $HOME/.config/omarchy/themes/$theme_name ]]; then
  echo "Theme '$theme_name' no longer exists; applying the default instead"
  omarchy-theme-set "Tokyo Night"
  exit 0
fi

current_colors="$HOME/.local/state/omarchy/current/theme/colors.toml"
source_colors="$HOME/.config/omarchy/themes/$theme_name/colors.toml"

stale=0
if [[ -f $current_colors ]]; then
  selection=$(awk -F'"' '/^selection = /{print $2; exit}' "$current_colors")
  foreground=$(awk -F'"' '/^foreground = /{print $2; exit}' "$current_colors")
  [[ -n $selection && $selection == "$foreground" ]] && stale=1
fi
if [[ -f $source_colors ]]; then
  selection=$(awk -F'"' '/^selection = /{print $2; exit}' "$source_colors")
  foreground=$(awk -F'"' '/^foreground = /{print $2; exit}' "$source_colors")
  [[ -n $selection && $selection == "$foreground" ]] && stale=1
fi

(( stale )) || exit 0

omarchy-theme-refresh
