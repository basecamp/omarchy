#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
matugen_calls="$test_tmp/matugen-calls"
package_calls="$test_tmp/package-calls"
theme_calls="$test_tmp/theme-calls"
mkdir -p "$mock_bin" "$test_home/.config/omarchy/themes" "$test_tmp/images"

cat >"$mock_bin/omarchy-cmd-missing" <<'STUB'
#!/bin/bash
[[ ${OMARCHY_TEST_MATUGEN_MISSING:-false} == "true" ]]
STUB

cat >"$mock_bin/omarchy-pkg-add" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_PACKAGE_CALLS"
STUB

cat >"$mock_bin/omarchy-theme-set" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_THEME_CALLS"
STUB

cat >"$mock_bin/matugen" <<'STUB'
#!/bin/bash

printf '%s\n' --call-- "$@" >>"$OMARCHY_TEST_MATUGEN_CALLS"
[[ ${OMARCHY_TEST_MATUGEN_FAIL:-false} == "true" ]] && exit 1

requested_mode="smart"
while (( $# > 0 )); do
  if [[ $1 == "--mode" ]]; then
    requested_mode="$2"
    break
  fi
  shift
done

if [[ $requested_mode == "light" ]]; then
  mode="light"
else
  mode="dark"
fi

cat <<JSON
{
  "mode": "$mode",
  "colors": {
    "primary": {"default": {"color": "#123456"}},
    "secondary_container": {"default": {"color": "#234567"}},
    "outline_variant": {"default": {"color": "#345678"}},
    "surface": {"default": {"color": "#222222"}},
    "surface_container_lowest": {"default": {"color": "#111111"}},
    "surface_container": {"default": {"color": "#eeeeee"}},
    "surface_container_highest": {"default": {"color": "#dddddd"}},
    "surface_container_low": {"default": {"color": "#f8f8f8"}},
    "shadow": {"default": {"color": "#000000"}},
    "on_surface": {"default": {"color": "#f0f0f0"}},
    "outline": {"default": {"color": "#777777"}},
    "on_surface_variant": {"default": {"color": "#cccccc"}},
    "red": {"default": {"color": "#aa0000"}},
    "yellow": {"default": {"color": "#aaaa00"}},
    "orange": {"default": {"color": "#aa5500"}},
    "green": {"default": {"color": "#00aa00"}},
    "cyan": {"default": {"color": "#00aaaa"}},
    "blue": {"default": {"color": "#0000aa"}},
    "magenta": {"default": {"color": "#aa00aa"}},
    "brown": {"default": {"color": "#775533"}},
    "on_red_container": {"default": {"color": "#ffaaaa"}},
    "on_yellow_container": {"default": {"color": "#ffffaa"}},
    "on_green_container": {"default": {"color": "#aaffaa"}},
    "on_cyan_container": {"default": {"color": "#aaffff"}},
    "on_blue_container": {"default": {"color": "#aaaaff"}},
    "on_magenta_container": {"default": {"color": "#ffaaff"}}
  }
}
JSON
STUB

chmod +x "$mock_bin"/*

run_theme() {
  : >"$test_tmp/stdout"
  : >"$test_tmp/stderr"

  HOME="$test_home" PATH="$mock_bin:$ROOT/bin:/usr/bin" OMARCHY_PATH="$ROOT" \
    OMARCHY_TEST_MATUGEN_CALLS="$matugen_calls" OMARCHY_TEST_PACKAGE_CALLS="$package_calls" \
    OMARCHY_TEST_THEME_CALLS="$theme_calls" \
    OMARCHY_TEST_MATUGEN_MISSING="${OMARCHY_TEST_MATUGEN_MISSING:-false}" \
    OMARCHY_TEST_MATUGEN_FAIL="${OMARCHY_TEST_MATUGEN_FAIL:-false}" \
    "$BASH" "$ROOT/bin/omarchy-theme-from-wallpaper" "$@" >"$test_tmp/stdout" 2>"$test_tmp/stderr"
}

wallpaper="$test_tmp/images/Sky View.WEBP"
printf 'wallpaper fixture\n' >"$wallpaper"
ln -s "$wallpaper" "$test_tmp/current-wallpaper"
: >"$matugen_calls"
: >"$package_calls"
: >"$theme_calls"

OMARCHY_TEST_MATUGEN_MISSING=true run_theme "$test_tmp/current-wallpaper" ||
  fail "a wallpaper theme is generated" "$(cat "$test_tmp/stderr")"

theme_path="$test_home/.config/omarchy/themes/wallpaper-sky-view"
[[ $(cat "$test_tmp/stdout") == "wallpaper-sky-view" ]] ||
  fail "the generated theme name is printed" "$(cat "$test_tmp/stdout")"
[[ -f $theme_path/backgrounds/wallpaper.webp ]] ||
  fail "the resolved wallpaper is copied with a supported extension"
cmp -s "$wallpaper" "$theme_path/backgrounds/wallpaper.webp" ||
  fail "the generated theme owns a byte-for-byte copy of the wallpaper"
grep -Fxq "matugen" "$package_calls" ||
  fail "matugen is installed on demand" "$(cat "$package_calls")"
grep -Fxq "$ROOT/default/omarchy/matugen-theme.toml" "$matugen_calls" ||
  fail "palette generation uses Omarchy's isolated Matugen config" "$(cat "$matugen_calls")"
grep -Fxq "$(realpath -e -- "$wallpaper")" "$matugen_calls" ||
  fail "Matugen receives the resolved image path so smart mode can inspect its extension" "$(cat "$matugen_calls")"
grep -Fxq "smart" "$matugen_calls" ||
  fail "wallpaper themes use smart mode by default" "$(cat "$matugen_calls")"

colors_file="$theme_path/colors.toml"
expected_keys=(
  accent selection muted
  background dark_background darker_background lighter_background
  foreground dark_foreground light_foreground bright_foreground
  red yellow orange green cyan blue magenta brown
  bright_red bright_yellow bright_green bright_cyan bright_blue bright_magenta
)

grep -Fxq 'mode = "dark"' "$colors_file" ||
  fail "smart mode records Matugen's chosen mode" "$(cat "$colors_file")"
for key in "${expected_keys[@]}"; do
  grep -Eq "^${key} = \"#[0-9a-f]{6}\"$" "$colors_file" ||
    fail "the generated palette includes $key as a valid hex color" "$(cat "$colors_file")"
done
grep -Fxq 'dark_background = "#111111"' "$colors_file" ||
  fail "dark themes use Matugen's lowest surface for dark_background" "$(cat "$colors_file")"
grep -Fxq 'darker_background = "#000000"' "$colors_file" ||
  fail "dark themes use Matugen's shadow for darker_background" "$(cat "$colors_file")"
grep -Fxq 'bright_red = "#ffaaaa"' "$colors_file" ||
  fail "dark themes use the brighter custom-color container text" "$(cat "$colors_file")"

HOME="$test_home" OMARCHY_PATH="$ROOT" "$BASH" "$ROOT/bin/omarchy-theme-color" --file "$colors_file" --all >/dev/null ||
  fail "the generated colors.toml is accepted by the shared theme resolver"

pass "a symlinked wallpaper generates a schema-complete standalone theme"

printf 'keep me\n' >"$theme_path/canary"
: >"$matugen_calls"
if run_theme "$wallpaper"; then
  fail "an existing theme requires --force"
fi
[[ $(cat "$theme_path/canary") == "keep me" ]] ||
  fail "refusing an overwrite leaves the existing theme untouched"
[[ ! -s $matugen_calls ]] ||
  fail "an existing theme is refused before palette generation" "$(cat "$matugen_calls")"

pass "existing themes are protected by default"

aurora_path="$test_home/.config/omarchy/themes/aurora"
mkdir -p "$aurora_path"
printf 'old theme\n' >"$aurora_path/canary"
: >"$matugen_calls"
: >"$theme_calls"
run_theme "$wallpaper" --name Aurora --mode light --force --apply ||
  fail "a named light theme can replace and apply an existing theme" "$(cat "$test_tmp/stderr")"

[[ $(cat "$test_tmp/stdout") == "aurora" ]] ||
  fail "explicit theme names are normalized and printed" "$(cat "$test_tmp/stdout")"
[[ ! -e $aurora_path/canary ]] ||
  fail "--force replaces the previous theme only after generation"
grep -Fxq "aurora" "$theme_calls" ||
  fail "--apply sends the generated theme through the normal setter" "$(cat "$theme_calls")"
grep -Fxq 'mode = "light"' "$aurora_path/colors.toml" ||
  fail "an explicit light mode reaches colors.toml" "$(cat "$aurora_path/colors.toml")"
grep -Fxq 'dark_background = "#eeeeee"' "$aurora_path/colors.toml" ||
  fail "light themes use a darker surface container" "$(cat "$aurora_path/colors.toml")"
grep -Fxq 'darker_background = "#dddddd"' "$aurora_path/colors.toml" ||
  fail "light themes use the highest surface container for the darker step" "$(cat "$aurora_path/colors.toml")"
grep -Fxq 'bright_red = "#aa0000"' "$aurora_path/colors.toml" ||
  fail "light themes keep readable base colors for bright ANSI slots" "$(cat "$aurora_path/colors.toml")"

pass "mode, naming, replacement, and optional application are explicit"

safe_path="$test_home/.config/omarchy/themes/safe"
mkdir -p "$safe_path"
printf 'original\n' >"$safe_path/colors.toml"
printf 'still safe\n' >"$safe_path/canary"

if OMARCHY_TEST_MATUGEN_FAIL=true run_theme "$wallpaper" --name safe --force; then
  fail "a failed palette extraction fails the command"
fi
[[ $(cat "$safe_path/colors.toml") == "original" ]] ||
  fail "a generation failure preserves the existing palette"
[[ $(cat "$safe_path/canary") == "still safe" ]] ||
  fail "a generation failure preserves the entire existing theme"
if find "$test_home/.config/omarchy/themes" -maxdepth 1 -name '.safe.*' -print -quit | grep -q .; then
  fail "a generation failure cleans its temporary theme"
fi

pass "failed generation is transactional even with --force"

: >"$matugen_calls"
printf 'not an image\n' >"$test_tmp/images/readme.txt"
for invalid_args in \
  "$wallpaper|--mode|dusk" \
  "$wallpaper|--name|../escape" \
  "$test_tmp/images/readme.txt"; do
  IFS='|' read -r -a args <<<"$invalid_args"
  if run_theme "${args[@]}"; then
    fail "invalid wallpaper arguments are rejected: $invalid_args"
  fi
done
[[ ! -s $matugen_calls ]] ||
  fail "invalid input is rejected before Matugen runs" "$(cat "$matugen_calls")"

pass "invalid modes, names, and image types are rejected before generation"
