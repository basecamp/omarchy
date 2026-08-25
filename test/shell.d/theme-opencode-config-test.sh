#!/bin/bash

set -euo pipefail

# colors-opencode.toml lets an installed theme carry its OpenCode integration
# back: pure TOML data that omarchy serializes into opencode.json, so nothing
# that runs code is shipped or executed. This suite locks the schema, the
# serialization, the escape hatch back to the generated template, and the fact
# that hostile strings stay strings.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

home="$test_tmp/home"
state="$home/.local/state/omarchy/current"
themes="$home/.config/omarchy/themes"
mkdir -p "$state" "$themes"

marker="omarchy-colors-opencode-marker"

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
    bash "$ROOT/bin/omarchy-theme-colors-opencode" "$@"
}

write_noir_config() {
  cat >"$1" <<TOML
schema = 1

[defs]
bg = "#1c1c1c"
panel = "#1c1c1c"
element = "#1c1c1c"
fg = "#c1c1c1"
bright = "#d1d1d1"
dim = "#666666"
muted = "#666666"
accent = "#8a9a7b"
accentBright = "#d1d1d1"
warm = "#8a9a7b"
grey = "#666666"
keyword = "#999999"
numeric = "#aa9988"
type = "#888888"
operator = "#aaaaaa"
line = "#333333"
addedBg = "#1c1c1c"
removedBg = "#1c1c1c"
ctxBg = "#1c1c1c"
TOML
}

# An installed theme may not ship opencode.json, but its declarative
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
bright_fg = "#d1d1d1"
darker_bg = "#1c1c1c"
TOML
write_noir_config "$noir/colors-opencode.toml"
printf '{"marker":"%s"}\n' "$marker" >"$noir/opencode.json"

set_theme noir-dawn || fail "omarchy-theme-set applies a theme carrying colors-opencode.toml"

assert_staged colors-opencode.toml "colors-opencode.toml is colour data and is staged"
! grep -q "$marker" "$(staged opencode.json)" || fail "an installed theme cannot ship opencode.json itself"
grep -q '"accent"' "$(staged opencode.json)" || fail "the theme's defs are serialized"
grep -q '#8a9a7b' "$(staged opencode.json)" || fail "accent hex color is serialized"
grep -q '"primary"' "$(staged opencode.json)" || fail "the theme mapping is serialized"

pass "an installed theme's colors-opencode.toml replaces the generated opencode.json"

golden="$test_tmp/golden.json"
cat >"$golden" <<'JSON'
{
  "$schema": "https://opencode.ai/theme.json",
  "defs": {
    "bg": "#1c1c1c",
    "panel": "#1c1c1c",
    "element": "#1c1c1c",
    "fg": "#c1c1c1",
    "bright": "#d1d1d1",
    "dim": "#666666",
    "muted": "#666666",
    "accent": "#8a9a7b",
    "accentBright": "#d1d1d1",
    "warm": "#8a9a7b",
    "grey": "#666666",
    "keyword": "#999999",
    "numeric": "#aa9988",
    "type": "#888888",
    "operator": "#aaaaaa",
    "line": "#333333",
    "addedBg": "#1c1c1c",
    "removedBg": "#1c1c1c",
    "ctxBg": "#1c1c1c"
  },
  "theme": {
    "primary": "accent",
    "secondary": "numeric",
    "accent": "accentBright",
    "error": "accent",
    "warning": "grey",
    "success": "type",
    "info": "numeric",
    "text": "fg",
    "textMuted": "muted",
    "background": "bg",
    "backgroundPanel": "panel",
    "backgroundElement": "element",
    "border": "accent",
    "borderActive": "accentBright",
    "borderSubtle": "line",
    "backgroundMenu": "panel",
    "selectedListItemText": "bg",
    "diffAdded": "fg",
    "diffRemoved": "warm",
    "diffContext": "dim",
    "diffHunkHeader": "grey",
    "diffHighlightAdded": "bright",
    "diffHighlightRemoved": "accentBright",
    "diffAddedBg": "addedBg",
    "diffRemovedBg": "removedBg",
    "diffContextBg": "ctxBg",
    "diffLineNumber": "muted",
    "diffAddedLineNumberBg": "panel",
    "diffRemovedLineNumberBg": "panel",
    "markdownText": "fg",
    "markdownHeading": "numeric",
    "markdownLink": "accentBright",
    "markdownLinkText": "warm",
    "markdownCode": "accentBright",
    "markdownBlockQuote": "dim",
    "markdownEmph": "accent",
    "markdownStrong": "bright",
    "markdownHorizontalRule": "line",
    "markdownListItem": "accent",
    "markdownListEnumeration": "accentBright",
    "markdownImage": "numeric",
    "markdownImageText": "warm",
    "markdownCodeBlock": "fg",
    "syntaxComment": "muted",
    "syntaxKeyword": "keyword",
    "syntaxFunction": "operator",
    "syntaxVariable": "fg",
    "syntaxString": "warm",
    "syntaxNumber": "numeric",
    "syntaxType": "type",
    "syntaxOperator": "operator",
    "syntaxPunctuation": "dim"
  }
}
JSON

diff -u "$golden" "$(staged opencode.json)" || fail "serialization is deterministic and matches the documented shape"

pass "the serialized opencode.json matches the documented shape exactly"

# A string value that tries to break out of its quotes comes out as one inert
# JSON string, whatever it contains. The [theme] section accepts any string
# reference, so a hostile value there tests JSON escaping.
hostile="$themes/hostile"
mkdir -p "$hostile/.git"
cp "$noir/colors.toml" "$hostile/colors.toml"
cat >"$hostile/colors-opencode.toml" <<TOML
schema = 1

[defs]
bg = "#1c1c1c"
panel = "#1c1c1c"
element = "#1c1c1c"
fg = "#c1c1c1"
bright = "#d1d1d1"
dim = "#666666"
muted = "#666666"
accent = "#8a9a7b"
accentBright = "#d1d1d1"
warm = "#8a9a7b"
grey = "#666666"
keyword = "#999999"
numeric = "#aa9988"
type = "#888888"
operator = "#aaaaaa"
line = "#333333"
addedBg = "#1c1c1c"
removedBg = "#1c1c1c"
ctxBg = "#1c1c1c"

[theme]
primary = "\"]},\"evil\":\"$marker"
TOML

set_theme hostile || fail "omarchy-theme-set applies a theme whose strings try to escape"
python3 -c "
import json, sys
data = json.load(open('$(staged opencode.json)'))
val = data['theme'].get('primary', '')
if not isinstance(val, str) or 'evil' not in val:
    sys.exit(1)
if data['theme'].get('evil'):
    sys.exit(2)
" || fail "a hostile value stays inside its quoted string"

pass "a string that tries to break out of its quotes stays a string"

# Anything the schema does not understand keeps the generated default and says
# so, instead of half-applying a theme's OpenCode config.
invalid_toml="$themes/invalid-toml"
mkdir -p "$invalid_toml/.git"
cp "$noir/colors.toml" "$invalid_toml/colors.toml"
printf '[defs]\nfg = "#c1c1c1"\n\n[theme]\nprimary = "unclosed\n' >"$invalid_toml/colors-opencode.toml"

set_theme invalid-toml || fail "an unparsable colors-opencode.toml does not break theme-set"
grep -qF '"primary"' "$(staged opencode.json)" || fail "an unparsable colors-opencode.toml keeps the generated default"
grep -q "colors-opencode" "$test_tmp/stderr" || fail "an unparsable colors-opencode.toml is named on stderr"

pass "an unparsable colors-opencode.toml falls back to the generated template loudly"

unknown_key="$themes/unknown-key"
mkdir -p "$unknown_key/.git"
cp "$noir/colors.toml" "$unknown_key/colors.toml"
printf 'loadstring = "evil"\n[defs]\nfg = "#c1c1c1"\n' >"$unknown_key/colors-opencode.toml"

set_theme unknown-key || fail "an unknown top-level key does not break theme-set"
grep -q "does not support the top-level key" "$test_tmp/stderr" || fail "an unknown top-level key is named on stderr"
grep -qF '"primary"' "$(staged opencode.json)" || fail "an unknown top-level key keeps the generated default"

pass "keys outside the schema are refused rather than ignored"

bad_schema="$themes/bad-schema"
mkdir -p "$bad_schema/.git"
cp "$noir/colors.toml" "$bad_schema/colors.toml"
printf 'schema = true\n[defs]\nfg = "#c1c1c1"\n' >"$bad_schema/colors-opencode.toml"

set_theme bad-schema || fail "a boolean schema value does not break theme-set"
grep -q "unsupported schema version" "$test_tmp/stderr" || fail "a boolean schema value is named on stderr"
grep -qF '"primary"' "$(staged opencode.json)" || fail "a boolean schema value keeps the generated default"

pass "the schema gate rejects non-integer versions like true"

no_defs="$themes/no-defs"
mkdir -p "$no_defs/.git"
cp "$noir/colors.toml" "$no_defs/colors.toml"
printf 'schema = 1\n' >"$no_defs/colors-opencode.toml"

set_theme no-defs || fail "a missing [defs] section does not break theme-set"
grep -q "defines no" "$test_tmp/stderr" || fail "a missing [defs] is named on stderr"

pass "a missing [defs] section is refused"

# A theme the user wrote gets the same treatment through the same door.
mine="$themes/mine"
mkdir -p "$mine"
cp "$noir/colors.toml" "$mine/colors.toml"
write_noir_config "$mine/colors-opencode.toml"

set_theme mine || fail "omarchy-theme-set applies a user-written theme with colors-opencode.toml"
grep -q '"accent"' "$(staged opencode.json)" || fail "a user-written theme's colors-opencode.toml is honored"

pass "a user-written theme's colors-opencode.toml is honored too"

# Direct renderer behaviour: losing python3 degrades to a refusal instead of a
# broken file.
values_toml="$test_tmp/values.toml"
cat >"$values_toml" <<TOML
schema = 1

[defs]
bg = "#1c1c1c"
panel = "#1c1c1c"
element = "#1c1c1c"
fg = "#c1c1c1"
bright = "#d1d1d1"
dim = "#666666"
muted = "#666666"
accent = "#8a9a7b"
accentBright = "#d1d1d1"
warm = "#8a9a7b"
grey = "#666666"
keyword = "#999999"
numeric = "#aa9988"
type = "#888888"
operator = "#aaaaaa"
line = "#333333"
addedBg = "#1c1c1c"
removedBg = "#1c1c1c"
ctxBg = "#1c1c1c"
TOML
values_out="$test_tmp/values-out.json"
render --file "$values_toml" --out "$values_out" || fail "the renderer reads the documented value zoo"
grep -q '"accent"' "$values_out" || fail "defs are serialized"

pass "hex colors serialize correctly"

out_without_python="$test_tmp/no-python.json"
if PATH= "$ROOT/bin/omarchy-theme-colors-opencode" --file "$values_toml" --out "$out_without_python" 2>"$test_tmp/stderr"; then
  fail "the renderer refuses to run without python3"
fi
grep -q "python3" "$test_tmp/stderr" || fail "losing python3 is explained on stderr"
[[ ! -e $out_without_python ]] || fail "nothing is written when the renderer refuses"

pass "without python3 the renderer refuses and writes nothing"

bad_args=0
render --file "$values_toml" 2>/dev/null || bad_args=1
(( bad_args == 1 )) || fail "the renderer requires both --file and --out"

pass "the renderer requires both --file and --out"
