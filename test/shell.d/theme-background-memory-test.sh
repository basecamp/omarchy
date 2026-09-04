#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

test_home="$test_tmp/home"
runtime_dir="$test_tmp/runtime"
current_state="$test_home/.local/state/omarchy/current"
background_state="$test_home/.local/state/omarchy/theme-backgrounds"
mkdir -p "$test_home" "$runtime_dir"

set_theme() {
  HOME="$test_home" XDG_RUNTIME_DIR="$runtime_dir" OMARCHY_PATH="$ROOT" PATH="$ROOT/bin:$PATH" \
    OMARCHY_THEME_HEADLESS=1 "$ROOT/bin/omarchy-theme-set" "$1" >/dev/null
}

current_background_name() {
  basename "$(readlink "$current_state/background")"
}

theme_a="tokyo-night"
theme_b="catppuccin"

set_theme "$theme_a"
mapfile -t theme_a_backgrounds < <(find "$current_state/theme/backgrounds" -maxdepth 1 -type f -print | sort)
(( ${#theme_a_backgrounds[@]} > 1 )) || fail "test theme has multiple backgrounds"
theme_a_first=${theme_a_backgrounds[0]##*/}
theme_a_selected_path=${theme_a_backgrounds[1]}
theme_a_selected=${theme_a_selected_path##*/}
ln -nsf "$theme_a_selected_path" "$current_state/background"

set_theme "$theme_b"
mapfile -t theme_b_backgrounds < <(find "$current_state/theme/backgrounds" -maxdepth 1 -type f -print | sort)
(( ${#theme_b_backgrounds[@]} > 1 )) || fail "second test theme has multiple backgrounds"
theme_b_first=${theme_b_backgrounds[0]##*/}

common_background=$(comm -12 \
  <(find "$ROOT/themes/$theme_a/backgrounds" -maxdepth 1 -type f -printf '%f\n' | sort) \
  <(find "$current_state/theme/backgrounds" -maxdepth 1 -type f -printf '%f\n' | sort) | head -n 1)
[[ -n $common_background ]] || fail "test themes share a background filename"
theme_b_common_path=$(find "$current_state/theme/backgrounds" -maxdepth 1 -type f -name "$common_background" -print -quit)
ln -nsf "$theme_b_common_path" "$current_state/background"

[[ $(<"$background_state/$theme_a") == "$theme_a_selected_path" ]] || fail "theme switch remembers the outgoing background path"
pass "theme switch remembers the outgoing background path"

set_theme "$theme_a"
[[ $(current_background_name) == "$theme_a_selected" ]] || fail "shared filenames do not override the remembered background"
pass "shared filenames do not override the remembered background"

set_theme "$theme_b"
[[ $(current_background_name) == "$common_background" ]] || fail "themes remember backgrounds independently"
pass "themes remember backgrounds independently"

external_background="$test_tmp/external-background.webp"
cp "$(readlink -f "$current_state/background")" "$external_background"
ln -nsf "$external_background" "$current_state/background"
set_theme "$theme_a"
set_theme "$theme_b"
[[ $(readlink -f "$current_state/background") == "$external_background" ]] || fail "theme switch restores an external background path"
pass "theme switch restores an external background path"

set_theme "$theme_b"
[[ $(current_background_name) == "$theme_b_first" ]] || fail "reapplying a theme with an external background falls back to the first image"
pass "reapplying a theme with an external background falls back to the first image"

set_theme "$theme_a"
user_background_dir="$test_home/.config/omarchy/backgrounds/$theme_a"
user_background="$user_background_dir/$theme_a_first"
mkdir -p "$user_background_dir"
cp "${theme_a_backgrounds[0]}" "$user_background"
ln -nsf "$user_background" "$current_state/background"
set_theme "$theme_b"
set_theme "$theme_a"
[[ $(readlink -f "$current_state/background") == "$user_background" ]] || fail "theme switch distinguishes duplicate background filenames"
pass "theme switch distinguishes duplicate background filenames"

set_theme "$theme_b"
rm -f "$user_background"
printf '%s\n' "$test_tmp/missing-background.webp" >"$background_state/$theme_a"
set_theme "$theme_a"
[[ $(current_background_name) == "$theme_a_first" ]] || fail "missing remembered background falls back to the first image"
pass "missing remembered background falls back to the first image"

set_theme "$theme_a"
[[ $(current_background_name) == "$theme_a_selected" ]] || fail "reapplying the active theme still cycles backgrounds"
pass "reapplying the active theme still cycles backgrounds"

printf '%s\n' "../escaped" >"$current_state/theme.name"
set_theme "$theme_b"
[[ ! -e $test_home/.local/state/omarchy/escaped ]] || fail "invalid theme names cannot escape the background state directory"
pass "invalid theme names cannot escape the background state directory"
