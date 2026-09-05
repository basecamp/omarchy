#!/bin/bash

set -euo pipefail

# neovim.toml restores editor-specific appearance for repository themes without
# allowing them to choose plugins or ship Lua. Omarchy validates the declaration
# and generates the fixed Aether v3 integration itself.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

home="$test_tmp/home"
state="$home/.local/state/omarchy/current"
themes="$home/.config/omarchy/themes"
mkdir -p "$state" "$themes"

marker="omarchy-neovim-marker"

write_colors() {
  cat >"$1" <<'TOML'
mode = "dark"
accent = "#7aa2f7"
selection = "#292e42"
muted = "#414868"
background = "#1a1b26"
dark_background = "#13141c"
darker_background = "#0e0e14"
lighter_background = "#24283b"
foreground = "#a9b1d6"
dark_foreground = "#565f89"
light_foreground = "#b4bee6"
bright_foreground = "#c0caf5"
red = "#f7768e"
green = "#9ece6a"
yellow = "#e0af68"
blue = "#7aa2f7"
magenta = "#bb9af7"
cyan = "#7dcfff"
TOML
}

write_declaration() {
  cat >"$1" <<'TOML'
schema = 1

[options]
transparent = true
terminal_colors = false
dim_inactive = true
lualine_bold = true

[styles]
sidebars = "transparent"
floats = "normal"

[styles.comments]
italic = false

[styles.keywords]
bold = true
italic = true

[colors]
bright_magenta = "#c1d7e3"
purple = "#9bb0c2"

[highlights.Keyword]
fg = "bright_magenta"
bold = true
italic = true

[highlights.Visual]
bg = "NONE"
blend = 20

[highlights."@keyword.function"]
link = "Function"
TOML
}

set_theme() {
  HOME="$home" OMARCHY_PATH="$ROOT" PATH="$ROOT/bin:$PATH" \
    OMARCHY_THEME_HEADLESS=1 OMARCHY_THEME_SKIP_BACKGROUND=1 \
    XDG_RUNTIME_DIR="$test_tmp" \
    bash "$ROOT/bin/omarchy-theme-set" "$1" 2>"$test_tmp/stderr"
}

staged() {
  printf '%s' "$state/theme/$1"
}

render() {
  OMARCHY_PATH="$ROOT" PATH="$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-theme-neovim" \
    --file "$1" --colors "$2" --out "$3"
}

# An installed overlay on a bundled theme may replace Omarchy's bundled
# neovim.lua through validated appearance data, while its own Lua is denied.
installed="$themes/tokyo-night"
mkdir -p "$installed/.git"
write_colors "$installed/colors.toml"
write_declaration "$installed/neovim.toml"
printf 'vim.cmd("%s")\n' "$marker" >"$installed/neovim.lua"

set_theme tokyo-night || fail "theme set accepts a valid installed neovim.toml"

lua_file=$(staged neovim.lua)
[[ -f $(staged neovim.toml) ]] || fail "installed neovim.toml is staged as appearance data"
[[ -f $lua_file ]] || fail "valid neovim.toml generates neovim.lua"
! grep -q "$marker" "$lua_file" || fail "repository neovim.lua remains denied"
(( $(grep -cF '"bjarneo/aether.nvim"' "$lua_file") == 1 )) || fail "generated Lua fixes the Aether plugin identity"
(( $(grep -cF 'branch = "v3"' "$lua_file") == 1 )) || fail "generated Lua fixes the Aether branch"
(( $(grep -cF '"LazyVim/LazyVim"' "$lua_file") == 1 )) || fail "generated Lua fixes the LazyVim identity"
grep -Fq 'colorscheme = "aether"' "$lua_file" || fail "generated Lua fixes the colorscheme"
grep -Fq 'transparent = true' "$lua_file" || fail "Neovim boolean options are rendered"
grep -Fq 'sidebars = "transparent"' "$lua_file" || fail "Neovim style variants are rendered"
grep -Fq 'bright_magenta = "#c1d7e3"' "$lua_file" || fail "Neovim palette overrides are rendered"
grep -Fq 'highlight["Keyword"] = { fg = colors["bright_magenta"], bold = true, italic = true }' "$lua_file" || fail "Neovim visual highlights are rendered"
grep -Fq 'highlight["Visual"] = { bg = "NONE", blend = 20 }' "$lua_file" || fail "Neovim transparent highlight backgrounds are rendered"
grep -Fq 'highlight["@keyword.function"] = "Function"' "$lua_file" || fail "Neovim highlight links are rendered"
! grep -Eq '(^|[[:space:]])(spec|build|config|init|dependencies|import)[[:space:]]*=' "$lua_file" || fail "generated Lua exposes no plugin-shaped declaration fields"

pass "installed neovim.toml generates only the fixed trusted Neovim integration"

if command -v luac >/dev/null; then
  luac -p "$lua_file" || fail "generated neovim.lua parses with luac"
  pass "generated neovim.lua parses with luac"
fi

if command -v nvim >/dev/null; then
  callback_check="$test_tmp/check-neovim.lua"
  cat >"$callback_check" <<LUA
local specs = assert(loadfile([[$lua_file]]))()
local highlights = {}
specs[1].opts.on_highlights(highlights, { bright_magenta = "#c1d7e3" })
assert(highlights.Keyword.fg == "#c1d7e3")
assert(highlights.Keyword.bold == true)
assert(highlights.Visual.bg == "NONE")
assert(highlights["@keyword.function"] == "Function")
LUA
  nvim --headless -u NONE "+lua dofile([[$callback_check]])" +qa >/dev/null 2>&1 || fail "generated neovim.lua loads and applies highlights in headless Neovim"
  pass "generated neovim.lua loads and applies highlights in headless Neovim without installing plugins"
fi

# Without a declaration, the ordinary colors.toml template remains unchanged.
plain="$themes/plain"
mkdir -p "$plain/.git"
write_colors "$plain/colors.toml"
set_theme plain || fail "theme set accepts a theme without neovim.toml"
grep -Fq 'bg = "#1a1b26"' "$(staged neovim.lua)" || fail "colors.toml still generates the normal Neovim palette"
! grep -Fq 'Generated by Omarchy from colors.toml and neovim.toml' "$(staged neovim.lua)" || fail "absent neovim.toml leaves the ordinary template output"

pass "absent neovim.toml preserves normal template generation"

# A malformed declaration fails closed after the normal template was generated.
invalid="$themes/invalid"
mkdir -p "$invalid/.git"
write_colors "$invalid/colors.toml"
printf 'schema = 1\nplugins = [{ spec = "evil/plugin.nvim" }]\n' >"$invalid/neovim.toml"
set_theme invalid || fail "an invalid neovim.toml falls back without aborting theme set"
grep -Fq '"bjarneo/aether.nvim"' "$(staged neovim.lua)" || fail "invalid neovim.toml retains the generated Aether fallback"
! grep -Fq 'evil/plugin.nvim' "$(staged neovim.lua)" || fail "plugin selection cannot reach generated Lua"
grep -Fq 'keeping the existing neovim.lua' "$test_tmp/stderr" || fail "invalid neovim.toml reports its fallback"

pass "invalid neovim.toml keeps the normal generated fallback"

# A handwritten local neovim.lua is trusted user code and remains authoritative.
local_theme="$themes/local"
mkdir -p "$local_theme"
write_colors "$local_theme/colors.toml"
write_declaration "$local_theme/neovim.toml"
printf 'return { "%s" }\n' "$marker" >"$local_theme/neovim.lua"
set_theme local || fail "theme set accepts a trusted local Neovim override"
grep -Fq "$marker" "$(staged neovim.lua)" || fail "trusted local neovim.lua wins over neovim.toml"

pass "trusted local neovim.lua retains precedence"

# The renderer rejects each schema escape without replacing an existing output.
render_dir="$test_tmp/render"
mkdir -p "$render_dir"
write_colors "$render_dir/colors.toml"

assert_rejected() {
  local name="$1"
  local declaration="$2"
  local output="$render_dir/$name.lua"
  local stderr="$render_dir/$name.stderr"

  printf '%s\n' "$marker" >"$output"
  if render "$declaration" "$render_dir/colors.toml" "$output" 2>"$stderr"; then
    fail "$name declaration is rejected"
  fi
  [[ $(cat "$output") == "$marker" ]] || fail "$name rejection leaves the existing output untouched"
}

cat >"$render_dir/plugin.toml" <<'TOML'
schema = 1
[[plugins]]
spec = "evil/plugin.nvim"
build = "touch /tmp/owned"
config = true
TOML
assert_rejected "plugin-shaped" "$render_dir/plugin.toml"

printf 'schema = [\n' >"$render_dir/malformed.toml"
assert_rejected "malformed" "$render_dir/malformed.toml"

printf 'schema = true\n' >"$render_dir/schema.toml"
assert_rejected "wrong-schema" "$render_dir/schema.toml"

cat >"$render_dir/types.toml" <<'TOML'
schema = 1
[options]
transparent = "yes"
TOML
assert_rejected "wrong-type" "$render_dir/types.toml"

cat >"$render_dir/color.toml" <<'TOML'
schema = 1
[colors]
accent = "red; os.execute('owned')"
TOML
assert_rejected "unsafe-color" "$render_dir/color.toml"

cat >"$render_dir/unknown.toml" <<'TOML'
schema = 1
[styles]
plugin = "evil"
TOML
assert_rejected "unknown-field" "$render_dir/unknown.toml"

cat >"$render_dir/conflicting-aliases.toml" <<'TOML'
schema = 1
[colors]
purple = "#112233"
magenta = "#445566"
TOML
assert_rejected "conflicting-aliases" "$render_dir/conflicting-aliases.toml"

cat >"$render_dir/hostile.toml" <<'TOML'
schema = 1
[highlights.'Keyword"]; vim.cmd("owned"); --']
fg = "red"
TOML
assert_rejected "hostile-name" "$render_dir/hostile.toml"

cat >"$render_dir/mixed-link.toml" <<'TOML'
schema = 1
[highlights.Keyword]
link = "Statement"
bold = true
TOML
assert_rejected "mixed-link" "$render_dir/mixed-link.toml"

printf 'schema = 1\n' >"$render_dir/oversized.toml"
truncate -s $((1024 * 1024 + 1)) "$render_dir/oversized.toml"
assert_rejected "oversized" "$render_dir/oversized.toml"

printf 'schema = 1\n' >"$render_dir/too-many.toml"
for index in $(seq 0 512); do
  printf '\n[highlights.Group%s]\nfg = "red"\n' "$index" >>"$render_dir/too-many.toml"
done
assert_rejected "too-many-highlights" "$render_dir/too-many.toml"

pass "renderer rejects plugin selection, malformed data, unsafe values, and schema limits atomically"
