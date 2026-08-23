#!/bin/bash

# An extra theme is a stranger's git repo. omarchy-theme-set stages only the
# files such a theme is allowed to contribute; everything else in the staged
# theme comes from Omarchy's own templates, so installing a theme never means
# running its code.

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

home="$test_tmp/home"
state="$home/.local/state/omarchy/current"
themes="$home/.config/omarchy/themes"
mkdir -p "$state" "$themes"

marker="omarchy-theme-staging-marker"

set_theme() {
  HOME="$home" OMARCHY_PATH="$ROOT" PATH="$ROOT/bin:$PATH" \
    OMARCHY_THEME_HEADLESS=1 OMARCHY_THEME_SKIP_BACKGROUND=1 \
    XDG_RUNTIME_DIR="$test_tmp" \
    bash "$ROOT/bin/omarchy-theme-set" "$1" 2>"$test_tmp/stderr"
}

staged() {
  printf '%s' "$state/theme/$1"
}

assert_staged() {
  [[ -f $(staged "$1") ]] || fail "$2"
}

assert_not_staged() {
  [[ ! -e $(staged "$1") ]] || fail "$2"
}

assert_no_marker() {
  grep -q "$marker" "$(staged "$1")" && fail "$2"
}

write_colors() {
  cat >"$1" <<TOML
mode = "light"

accent = "#7aa2f7"
selection = "#292e42"
muted = "#414868"

background = "#1a1b26"
foreground = "#a9b1d6"

color0 = "#1a1b26"
color1 = "#f7768e"
color2 = "#9ece6a"
color3 = "#e0af68"
color4 = "#7aa2f7"
color5 = "#bb9af7"
color6 = "#7dcfff"
color7 = "#a9b1d6"
TOML
}

# A theme that ships everything it is not allowed to ship.
hostile="$themes/hostile"
mkdir -p "$hostile/backgrounds"
write_colors "$hostile/colors.toml"
touch "$hostile/light.mode"
printf 'os.execute("%s")\n' "$marker" >"$hostile/hyprland.lua"
printf 'vim.cmd("%s")\n' "$marker" >"$hostile/neovim.lua"
printf 'shell %s\n' "$marker" >"$hostile/kitty.conf"
printf '[terminal.shell]\nprogram = "%s"\n' "$marker" >"$hostile/alacritty.toml"
printf 'shell = "%s"\n' "$marker" >"$hostile/foot.ini"
printf 'command = "%s"\n' "$marker" >"$hostile/ghostty.conf"
printf 'hl.env("GUM_INPUT_PROMPT", "%s")\n' "$marker" >"$hostile/gum_env.lua"
printf '[bar]\nbackground = "#%s"\n' "000000" >"$hostile/shell.toml"
printf '{}\n' >"$hostile/vscode.json"
printf '%s\n' "$marker" >"$hostile/icons.theme"
printf '%s\n' "$marker" >"$hostile/btop.theme"
printf 'png\n' >"$hostile/preview.png"
printf 'png\n' >"$hostile/backgrounds/1-real.png"
printf '%s\n' "$marker" >"$hostile/backgrounds/payload.sh"
printf '# notes\n' >"$hostile/README.md"
ln -s /etc/hostname "$hostile/unlock.png"

set_theme hostile || fail "omarchy-theme-set applies a theme that ships disallowed files"

assert_staged colors.toml "the theme's colors.toml is staged"
grep -q '#7aa2f7' "$(staged colors.toml)" || fail "the staged colors.toml is the theme's palette"
assert_staged light.mode "the light mode marker is staged"
assert_staged preview.png "the theme's preview image is staged"
assert_staged backgrounds/1-real.png "an image in backgrounds/ is staged"

assert_not_staged backgrounds/payload.sh "a non-image in backgrounds/ is not staged"
assert_not_staged unlock.png "a symlink is not followed out of the theme"
assert_not_staged icons.theme "icons.theme is outside the allowlist and is not staged"
assert_not_staged vscode.json "vscode.json is outside the allowlist and is not staged"

# These names are generated from Omarchy's templates, so the theme's versions
# must lose rather than merely be absent.
for generated in hyprland.lua neovim.lua kitty.conf alacritty.toml foot.ini ghostty.conf gum_env.lua shell.toml btop.theme; do
  assert_staged "$generated" "$generated is generated from Omarchy's template"
  assert_no_marker "$generated" "an extra theme cannot supply $generated"
done

grep -q 'hyprland.lua' "$test_tmp/stderr" || fail "omarchy-theme-set names the files it ignored"
grep -q 'README.md' "$test_tmp/stderr" && fail "omarchy-theme-set does not report a theme's documentation"

pass "an extra theme contributes only its palette, images, and light mode marker"

# A theme predating colors.toml still gets a palette, without its alacritty.toml
# reaching the staged theme.
legacy="$themes/legacy"
mkdir -p "$legacy"
cat >"$legacy/alacritty.toml" <<TOML
[terminal.shell]
program = "$marker"

[colors.primary]
background = "#102030"
foreground = "#a0b0c0"

[colors.normal]
black = "#102030"
red = "#ff0000"
green = "#00ff00"
yellow = "#ffff00"
blue = "#0000ff"
magenta = "#ff00ff"
cyan = "#00ffff"
white = "#a0b0c0"
TOML

set_theme legacy || fail "omarchy-theme-set applies a theme that only ships alacritty.toml"
assert_staged colors.toml "a legacy theme's palette is recovered from its alacritty.toml"
grep -q '#102030' "$(staged colors.toml)" || fail "the recovered palette is the theme's"
assert_no_marker alacritty.toml "a legacy theme's alacritty.toml is not staged"

pass "a theme older than colors.toml keeps its palette and loses its terminal config"

# An overlay on a stock theme still repaints it, and still cannot add code.
mkdir -p "$themes/tokyo-night"
write_colors "$themes/tokyo-night/colors.toml"
sed -i 's/#7aa2f7/#abcdef/' "$themes/tokyo-night/colors.toml"
printf 'os.execute("%s")\n' "$marker" >"$themes/tokyo-night/hyprland.lua"

set_theme "Tokyo Night" || fail "omarchy-theme-set applies a stock theme with a user overlay"
grep -q '#abcdef' "$(staged colors.toml)" || fail "a user overlay still replaces the stock palette"
assert_no_marker hyprland.lua "a user overlay cannot add Lua to a stock theme"

pass "an overlay on a stock theme repaints it without adding code"

# The name is joined into paths that get removed and copied into.
for name in .. . "../../evil"; do
  set_theme "$name" >/dev/null && fail "omarchy-theme-set rejects the theme name '$name'"
done

pass "a theme name cannot climb out of the theme directories"
