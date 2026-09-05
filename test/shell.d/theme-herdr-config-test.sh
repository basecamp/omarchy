#!/bin/bash

set -euo pipefail

# colors-herdr.toml lets an installed theme carry its Herdr integration back:
# pure TOML data that omarchy serializes into herdr-theme.toml, so nothing that
# runs code is shipped or executed. This suite locks the schema, the
# serialization, the config patching, and the fact that hostile strings stay
# strings.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

home="$test_tmp/home"
state="$home/.local/state/omarchy/current"
themes="$home/.config/omarchy/themes"
herdr_config="$home/.config/herdr"
mkdir -p "$state" "$themes" "$herdr_config"

marker="omarchy-colors-herdr-marker"

set_theme() {
  HOME="$home" OMARCHY_PATH="$ROOT" PATH="$ROOT/bin:$PATH" \
    OMARCHY_THEME_HEADLESS=1 OMARCHY_THEME_SKIP_BACKGROUND=1 \
    XDG_RUNTIME_DIR="$test_tmp" \
    bash "$ROOT/bin/omarchy-theme-set" "$1" 2>"$test_tmp/stderr" || return $?
}

staged() {
  printf '%s' "$state/theme/$1"
}

assert_staged() {
  [[ -f $(staged "$1") ]] || fail "$2"
}

render() {
  HOME="$home" OMARCHY_PATH="$ROOT" PATH="$ROOT/bin:$PATH" \
    bash "$ROOT/bin/omarchy-theme-colors-herdr" "$@"
}

write_herdr_config() {
  cat >"$1" <<TOML
[theme]
name = "terminal"

[theme.custom]
panel_bg = "black"

[keys]
prefix = "ctrl+space"

[ui]
accent = "blue"
TOML
}

write_noir_config() {
  cat >"$1" <<TOML
schema = 1

[theme]
name = "terminal"

[theme.custom]
accent = "#8a9a7b"
panel_bg = "#1c1c1c"
sidebar_bg = "#0c0b0c"
active_row_bg = "#333333"
selection_bg = "#444444"
surface0 = "#333333"
surface1 = "#444444"
surface_dim = "#0c0b0c"
overlay0 = "#666666"
overlay1 = "#777777"
text = "#c1c1c1"
subtext0 = "#aaaaaa"
mauve = "#999999"
green = "#c1c1c1"
yellow = "#888888"
red = "#8a9a7b"
blue = "#aaaaaa"
teal = "#aa9988"
peach = "#9ca98f"
TOML
}

# Set up a default herdr config
write_herdr_config "$herdr_config/config.toml"

# An installed theme may not ship herdr-theme.toml, but its declarative
# integration replaces the generated one.
noir="$themes/noir-dawn"
mkdir -p "$noir/.git"
cat >"$noir/colors.toml" <<TOML
mode = "dark"
background = "#1c1c1c"
foreground = "#c1c1c1"
accent = "#8a9a7b"
red = "#8a9a7b"
green = "#c1c1c1"
yellow = "#888888"
blue = "#aaaaaa"
magenta = "#999999"
cyan = "#aa9988"
muted = "#666666"
TOML
write_noir_config "$noir/colors-herdr.toml"
printf '# %s\n' "$marker" >"$noir/herdr-theme.toml"

set_theme noir-dawn || fail "omarchy-theme-set applies a theme carrying colors-herdr.toml"

assert_staged colors-herdr.toml "colors-herdr.toml is colour data and is staged"
assert_staged herdr-theme.toml "herdr-theme.toml is generated from colors-herdr.toml"
grep -q "accent" "$(staged herdr-theme.toml)" || fail "the theme's accent is serialized"
grep -q '#8a9a7b' "$(staged herdr-theme.toml)" || fail "the accent hex color is serialized"

pass "an installed theme's colors-herdr.toml produces herdr-theme.toml"

golden="$test_tmp/golden.toml"
cat >"$golden" <<'TOML'
[theme]
name = "terminal"

[theme.custom]
accent = "#8a9a7b"
panel_bg = "#1c1c1c"
sidebar_bg = "#0c0b0c"
active_row_bg = "#333333"
selection_bg = "#444444"
surface0 = "#333333"
surface1 = "#444444"
surface_dim = "#0c0b0c"
overlay0 = "#666666"
overlay1 = "#777777"
text = "#c1c1c1"
subtext0 = "#aaaaaa"
mauve = "#999999"
green = "#c1c1c1"
yellow = "#888888"
red = "#8a9a7b"
blue = "#aaaaaa"
teal = "#aa9988"
peach = "#9ca98f"
TOML

diff -u "$golden" "$(staged herdr-theme.toml)" || fail "serialization is deterministic and matches the documented shape"

pass "the serialized herdr-theme.toml matches the documented shape exactly"

# The herdr-theme-set command patches the user's config.toml
cp "$herdr_config/config.toml" "$herdr_config/config.toml.bak"
HOME="$home" OMARCHY_PATH="$ROOT" PATH="$ROOT/bin:$PATH" \
  bash "$ROOT/bin/omarchy-theme-set-herdr"

grep -q '#8a9a7b' "$herdr_config/config.toml" || fail "herdr config.toml is patched with the accent color"
grep -q 'panel_bg = "#1c1c1c"' "$herdr_config/config.toml" || fail "herdr config.toml is patched with panel_bg"
grep -q 'prefix = "ctrl+space"' "$herdr_config/config.toml" || fail "non-theme settings are preserved"

pass "omarchy-theme-set-herdr patches the user's config.toml"

# A string value that tries to break out of its quotes comes out as one inert
# TOML string, whatever it contains.
hostile="$themes/hostile"
mkdir -p "$hostile/.git"
cp "$noir/colors.toml" "$hostile/colors.toml"
cat >"$hostile/colors-herdr.toml" <<TOML
schema = 1

[theme]
name = "terminal"

[theme.custom]
accent = "#8a9a7b"
panel_bg = "\"]; os.execute(\"$marker\") --"
TOML

set_theme hostile || fail "omarchy-theme-set applies a theme whose strings try to escape"
! grep -qF '\"]; os.execute' "$(staged herdr-theme.toml)" || fail "a hostile value never appears in the staged file"
! grep -q "$marker" "$(staged herdr-theme.toml)" || fail "a hostile value never becomes TOML code on its own"
grep -q 'accent = "#8a9a7b"' "$(staged herdr-theme.toml)" || fail "the template fallback produces clean output"

pass "a string that tries to break out of its quotes is rejected and the template fallback is used"

# Anything the schema does not understand keeps the generated default and says
# so, instead of half-applying a theme's Herdr config.
invalid_toml="$themes/invalid-toml"
mkdir -p "$invalid_toml/.git"
cp "$noir/colors.toml" "$invalid_toml/colors.toml"
printf '[theme]\nname = "terminal"\n\n[theme.custom]\naccent = "#8a9a7b"\n\n[theme.foo]\nbar = "baz\n' >"$invalid_toml/colors-herdr.toml"

set_theme invalid-toml || fail "an unparsable colors-herdr.toml does not break theme-set"
grep -qF '"terminal"' "$(staged herdr-theme.toml)" || fail "an unparsable colors-herdr.toml keeps the generated default"
grep -q "colors-herdr" "$test_tmp/stderr" || fail "an unparsable colors-herdr.toml is named on stderr"

pass "an unparsable colors-herdr.toml falls back to the generated template loudly"

unknown_key="$themes/unknown-key"
mkdir -p "$unknown_key/.git"
cp "$noir/colors.toml" "$unknown_key/colors.toml"
printf 'loadstring = "evil"\n[theme]\nname = "terminal"\n' >"$unknown_key/colors-herdr.toml"

set_theme unknown-key || fail "an unknown top-level key does not break theme-set"
grep -q "does not support the top-level key" "$test_tmp/stderr" || fail "an unknown top-level key is named on stderr"
grep -qF '"terminal"' "$(staged herdr-theme.toml)" || fail "an unknown top-level key keeps the generated default"

pass "keys outside the schema are refused rather than ignored"

bad_schema="$themes/bad-schema"
mkdir -p "$bad_schema/.git"
cp "$noir/colors.toml" "$bad_schema/colors.toml"
printf 'schema = true\n[theme]\nname = "terminal"\n' >"$bad_schema/colors-herdr.toml"

set_theme bad-schema || fail "a boolean schema value does not break theme-set"
grep -q "unsupported schema version" "$test_tmp/stderr" || fail "a boolean schema value is named on stderr"
grep -qF '"terminal"' "$(staged herdr-theme.toml)" || fail "a boolean schema value keeps the generated default"

pass "the schema gate rejects non-integer versions like true"

no_theme="$themes/no-theme"
mkdir -p "$no_theme/.git"
cp "$noir/colors.toml" "$no_theme/colors.toml"
printf 'schema = 1\n' >"$no_theme/colors-herdr.toml"

set_theme no-theme || fail "a missing [theme] section does not break theme-set"
grep -q "defines no" "$test_tmp/stderr" || fail "a missing [theme] is named on stderr"

pass "a missing [theme] section is refused"

# A theme the user wrote gets the same treatment through the same door.
mine="$themes/mine"
mkdir -p "$mine"
cp "$noir/colors.toml" "$mine/colors.toml"
write_noir_config "$mine/colors-herdr.toml"

set_theme mine || fail "omarchy-theme-set applies a user-written theme with colors-herdr.toml"
grep -q '#8a9a7b' "$(staged herdr-theme.toml)" || fail "a user-written theme's colors-herdr.toml is honored"

pass "a user-written theme's colors-herdr.toml is honored too"

# Direct renderer behaviour: losing python3 degrades to a refusal instead of a
# broken file.
values_toml="$test_tmp/values.toml"
cat >"$values_toml" <<TOML
schema = 1

[theme]
name = "terminal"
auto_switch = true

[theme.custom]
accent = "#8a9a7b"
panel_bg = "#1c1c1c"
TOML
values_out="$test_tmp/values-out.toml"
render --file "$values_toml" --out "$values_out" || fail "the renderer reads the documented value zoo"
grep -q "auto_switch = true" "$values_out" || fail "booleans serialize"
grep -q '#8a9a7b' "$values_out" || fail "hex colors serialize"

pass "booleans and hex colors serialize correctly"

out_without_python="$test_tmp/no-python.toml"
if PATH= "$ROOT/bin/omarchy-theme-colors-herdr" --file "$values_toml" --out "$out_without_python" 2>"$test_tmp/stderr"; then
  fail "the renderer refuses to run without python3"
fi
grep -q "python3" "$test_tmp/stderr" || fail "losing python3 is explained on stderr"
[[ ! -e $out_without_python ]] || fail "nothing is written when the renderer refuses"

pass "without python3 the renderer refuses and writes nothing"

bad_args=0
render --file "$values_toml" 2>/dev/null || bad_args=1
(( bad_args == 1 )) || fail "the renderer requires both --file and --out"

pass "the renderer requires both --file and --out"
