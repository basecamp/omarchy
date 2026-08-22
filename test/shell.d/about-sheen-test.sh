#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# The launcher ends by taking over the process, so source it short of that line
# and its half of the question can be asked here, without a terminal to draw on.
about="$ROOT/bin/omarchy-launch-about"
grep -q '^presize_window$' "$about" || fail "About launcher can be sourced short of its launch"
sed '/^presize_window$/,$d' "$about" >"$tmp_dir/about.bash"

export HOME="$tmp_dir/home"
export PATH="$ROOT/bin:$PATH"
mkdir -p "$HOME/.config/omarchy/branding"
printf '%s\n' '████████' '████████' >"$HOME/.config/omarchy/branding/about.txt"

source "$tmp_dir/about.bash"
[[ $(type -t sheen_build) == "function" ]] || fail "the launcher finds the sheen it sources"
pass "the launcher finds the sheen it sources"

# Stand in for the terminal, and for the fastfetch run that measures the layout.
rows_by_cols="45 140"
layout_rows=20
logo_color=$'\e[1m\e[32m'
stty() { printf '%s\n' "$rows_by_cols"; }
measure_layout() {
  LAYOUT_ROWS=$layout_rows
  LOGO_COLOR=$logo_color
}

# fastfetch resolves the home directory from the passwd database rather than
# $HOME, so it would answer for the real one. Stand in for it with the search
# order it prints, pointed at this test's directories.
config_paths=(
  "$HOME/.config/fastfetch/"
  "$HOME/fastfetch/"
  "$OMARCHY_FASTFETCH_DIR/ (*)"
  "$HOME/searched-later/fastfetch/"
)
fastfetch() {
  [[ ${1:-} == "--list-config-paths" ]] || return 1
  printf '%s\n' "${config_paths[@]}"
}

# Record what the launcher hands the sheen rather than building any frames.
handed=()
sheen_build() { handed=("$@"); }

refuses() {
  if build_sheen; then
    fail "$1"
  else
    pass "$1"
  fi
}

# The sheen repaints the cells fastfetch drew the logo on, so the launcher's idea
# of the padding has to be the config's. Read them from the config rather than
# from the launcher, or a drift between the two would agree with itself.
config_top=$(jq -r '.logo.padding.top' "$ROOT/etc/fastfetch/config.jsonc")
config_left=$(jq -r '.logo.padding.left' "$ROOT/etc/fastfetch/config.jsonc")
config_right=$(jq -r '.logo.padding.right' "$ROOT/etc/fastfetch/config.jsonc")

[[ $LOGO_PAD_TOP == "$config_top" && $LOGO_PAD_LEFT == "$config_left" && $LOGO_PAD_RIGHT == "$config_right" ]] ||
  fail "the launcher's padding is the fastfetch config's" "config: $config_top/$config_left/$config_right, launcher: $LOGO_PAD_TOP/$LOGO_PAD_LEFT/$LOGO_PAD_RIGHT"
pass "the launcher's padding is the fastfetch config's"

build_sheen || fail "a roomy window animates"
pass "a roomy window animates"

# The sheen is told where the logo is, what colour to hand the cells back in, and
# how much room it has left of the module column.
[[ ${handed[0]} == "$HOME/.config/omarchy/branding/about.txt" ]] || fail "the sheen is given the logo About draws" "${handed[0]}"
pass "the sheen is given the logo About draws"
[[ ${handed[1]} == "$config_top" && ${handed[2]} == "$config_left" ]] || fail "the sheen is given the config's padding" "${handed[1]}/${handed[2]}"
pass "the sheen is given the config's padding"
[[ ${handed[3]} == $'\e[0m'"$logo_color" ]] || fail "the sheen is given fastfetch's own colour to restore" "$(printf '%q' "${handed[3]}")"
pass "the sheen is given fastfetch's own colour to restore"
[[ ${handed[4]} == "$((140 - config_left))" ]] || fail "the sheen is given the columns left of the module column" "${handed[4]}"
pass "the sheen is given the columns left of the module column"

# fastfetch reads the first config it finds across several directories, and any
# of them ahead of Omarchy's own can put the logo somewhere else entirely.
for directory in .config/fastfetch fastfetch; do
  mkdir -p "$HOME/$directory"
  touch "$HOME/$directory/config.jsonc"
  refuses "a fastfetch config in ~/$directory leaves the logo still"
  rm -r "${HOME:?}/$directory"
done

# One fastfetch would never read, because Omarchy's own comes first, is not a
# reason to stop: the logo on screen is still the one About drew.
mkdir -p "$HOME/searched-later/fastfetch"
touch "$HOME/searched-later/fastfetch/config.jsonc"
build_sheen || fail "a config fastfetch searches after Omarchy's own still animates"
pass "a config fastfetch searches after Omarchy's own still animates"
rm -r "${HOME:?}/searched-later"

# A window with no room for the cursor past the layout's last line has scrolled,
# and the logo is no longer on the rows the frames address.
rows_by_cols="$((layout_rows + 1)) 140"
build_sheen || fail "a window with one row past the layout animates"
pass "a window with one row past the layout animates"
rows_by_cols="$layout_rows 140"
refuses "a window level with the layout's last line leaves it still"
rows_by_cols="45 140"

# fastfetch drops the logo's colour for a terminal that asked for none, but not
# for the measurement, so the colour to restore would be measured wrong — and a
# glint is colour besides.
NO_COLOR=1
refuses "a session that asked for no colour leaves the logo still"
unset NO_COLOR

# A home directory may contain a space, and the marker fastfetch puts beside the
# config it settled on is not part of the path.
spacey="$tmp_dir/example user/.config/fastfetch"
mkdir -p "$spacey"
touch "$spacey/config.jsonc"
config_paths=("$tmp_dir/example user/.config/fastfetch/" "$OMARCHY_FASTFETCH_DIR/ (*)")
custom_fastfetch_config || fail "a fastfetch config in a path with a space is found"
pass "a fastfetch config in a path with a space is found"
rm -r "$tmp_dir/example user"
config_paths=("$HOME/.config/fastfetch/" "$HOME/fastfetch/" "$OMARCHY_FASTFETCH_DIR/ (*)")

# An enumeration that said nothing is not the same answer as "none of them".
mkdir -p "$HOME/.config/fastfetch"
touch "$HOME/.config/fastfetch/config.jsonc"
listing=$(declare -f fastfetch)
fastfetch() { return 7; }
custom_fastfetch_config || fail "an enumeration that failed does not read as no config"
pass "an enumeration that failed does not read as no config"
eval "$listing"
rm -r "${HOME:?}/.config/fastfetch"

# The grid costs a process and is only read on the poll interval, so a resize can
# land while it is being read. The sweep has to see that before it paints again.
SHEEN_FRAMES=("first" "second" "third")
tick() { :; }
resized=false
content_changed() { resized=true; return 1; }
painted=$(play_sheen || true)
[[ -z $painted ]] || fail "a resize landing during the check stops the sweep before it paints" "$(printf '%q' "$painted")"
pass "a resize landing during the check stops the sweep before it paints"

resized=false
content_changed() { return 1; }
painted=$(play_sheen || true)
[[ $painted == "firstsecondthird" ]] || fail "an undisturbed sweep writes every frame" "$(printf '%q' "$painted")"
pass "an undisturbed sweep writes every frame"

measure_layout() { return 1; }
refuses "a layout fastfetch cannot be measured from leaves it still"

# Once the logo is taller than the module column, fastfetch writes a row more
# than logo-plus-padding, so a window sized by that arithmetic scrolls its top
# padding away — and a scrolled layout is one the sheen then refuses. The fit
# asks fastfetch how tall the layout came out instead.
rm -rf "${HOME:?}/.local"
printf '%s\n' $(for i in $(seq 40); do echo '██████████'; done) >"$HOME/.config/omarchy/branding/about.txt"
layout_rows=43
measure_layout() {
  LAYOUT_ROWS=$layout_rows
  LOGO_COLOR=$logo_color
}
fastfetch() {
  case ${1:-} in
    --list-config-paths) printf '%s\n' "${config_paths[@]}" ;;
    --logo) for i in $(seq 29); do printf '%065d\n' 0; done ;;
    *) return 1 ;;
  esac
}
hyprctl() {
  [[ $1 == "clients" ]] && printf '[{"class":"org.omarchy.about","address":"0x1","size":[800,600]}]\n'
  return 0
}

# logo 10 wide + the config's padding + a 65-column module block.
fit_cols=$(( config_left + 10 + config_right + 65 + config_left ))

rows_by_cols="$((layout_rows + 1)) $fit_cols"
fit_window || fail "the fit is satisfied by a window with a row past the layout"
pass "the fit is satisfied by a window with a row past the layout"

rows_by_cols="$layout_rows $fit_cols"
if fit_window; then
  fail "the fit is not satisfied by a window that scrolls the layout"
else
  pass "the fit is not satisfied by a window that scrolls the layout"
fi
