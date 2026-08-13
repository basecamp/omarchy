#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

codex_config="$test_dir/codex/config.toml"
grok_config="$test_dir/grok/config.toml"

mkdir -p "$(dirname "$codex_config")" "$(dirname "$grok_config")"
cat >"$codex_config" <<'EOF'
model = "gpt-5.6"

[tui]
theme = "catppuccin-latte"
notifications = false

[features]
multi_agent = true
EOF
cat >"$grok_config" <<'EOF'
[ui]
theme = "auto"
screen_mode = "alternate"

[privacy]
analytics = false
EOF

CODEX_CONFIG_PATH="$codex_config" "$ROOT/bin/omarchy-theme-set-codex"
GROK_CONFIG_PATH="$grok_config" "$ROOT/bin/omarchy-theme-set-grok"
grep -Fxq 'theme = "catppuccin-latte"' "$codex_config" || fail "Codex helper changes the theme without activation"
grep -Fxq 'theme = "auto"' "$grok_config" || fail "Grok helper changes the theme without activation"
pass "terminal palette helpers do nothing during ordinary theme switches"

CODEX_CONFIG_PATH="$codex_config" "$ROOT/bin/omarchy-theme-set-codex" --activate
GROK_CONFIG_PATH="$grok_config" "$ROOT/bin/omarchy-theme-set-grok" --activate

grep -Fxq 'theme = "ansi"' "$codex_config" || fail "Codex helper does not select its ANSI theme"
grep -Fxq 'model = "gpt-5.6"' "$codex_config" || fail "Codex helper loses top-level preferences"
grep -Fxq 'notifications = false' "$codex_config" || fail "Codex helper loses TUI preferences"
grep -Fxq 'multi_agent = true' "$codex_config" || fail "Codex helper loses feature preferences"
grep -Fxq 'theme = "minimal"' "$grok_config" || fail "Grok helper does not select its terminal palette theme"
grep -Fxq 'screen_mode = "alternate"' "$grok_config" || fail "Grok helper changes screen mode"
grep -Fxq 'analytics = false' "$grok_config" || fail "Grok helper loses privacy preferences"
pass "terminal palette helpers preserve unrelated settings"

codex_before=$(sha256sum "$codex_config")
grok_before=$(sha256sum "$grok_config")
CODEX_CONFIG_PATH="$codex_config" "$ROOT/bin/omarchy-theme-set-codex" --activate
GROK_CONFIG_PATH="$grok_config" "$ROOT/bin/omarchy-theme-set-grok" --activate
[[ $codex_before == $(sha256sum "$codex_config") ]] || fail "Codex activation is not idempotent"
[[ $grok_before == $(sha256sum "$grok_config") ]] || fail "Grok activation is not idempotent"
pass "terminal palette activation is idempotent"

printf 'tui.theme = "dracula"\nmodel = "keep-me"\n' >"$codex_config"
printf 'ui.theme = "auto"\nmodel = "keep-me"\n' >"$grok_config"
CODEX_CONFIG_PATH="$codex_config" "$ROOT/bin/omarchy-theme-set-codex" --activate
GROK_CONFIG_PATH="$grok_config" "$ROOT/bin/omarchy-theme-set-grok" --activate
grep -Fxq 'tui.theme = "ansi"' "$codex_config" || fail "Codex helper does not support a dotted theme key"
grep -Fxq 'ui.theme = "minimal"' "$grok_config" || fail "Grok helper does not support a dotted theme key"
[[ $(grep -c '^\[tui\]$' "$codex_config") == 0 ]] || fail "Codex helper duplicates a dotted theme setting"
[[ $(grep -c '^\[ui\]$' "$grok_config") == 0 ]] || fail "Grok helper duplicates a dotted theme setting"
pass "terminal palette helpers support dotted TOML keys"

mkdir -p "$test_dir/dotfiles"
printf '[tui]\ntheme = "solarized"\n' >"$test_dir/dotfiles/codex.toml"
printf '[ui]\ntheme = "auto"\n' >"$test_dir/dotfiles/grok.toml"
ln -sf "$test_dir/dotfiles/codex.toml" "$codex_config"
ln -sf "$test_dir/dotfiles/grok.toml" "$grok_config"
CODEX_CONFIG_PATH="$codex_config" "$ROOT/bin/omarchy-theme-set-codex" --activate
GROK_CONFIG_PATH="$grok_config" "$ROOT/bin/omarchy-theme-set-grok" --activate
[[ -L $codex_config && -L $grok_config ]] || fail "terminal palette helpers replace config symlinks"
grep -Fxq 'theme = "ansi"' "$test_dir/dotfiles/codex.toml" || fail "Codex helper does not write through a symlink"
grep -Fxq 'theme = "minimal"' "$test_dir/dotfiles/grok.toml" || fail "Grok helper does not write through a symlink"
pass "terminal palette helpers preserve dotfile symlinks"
