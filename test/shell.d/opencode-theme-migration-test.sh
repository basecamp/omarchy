#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command jq

migration="$ROOT/migrations/1787871792.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

plugin_spec="$ROOT/config/opencode/tui-plugins/omarchy-theme.ts"

run_migration() {
  HOME="$test_dir/home" OMARCHY_PATH="$ROOT" PATH="$ROOT/bin:$PATH" \
    env -u XDG_CONFIG_HOME -u OPENCODE_CONFIG_DIR bash -euo pipefail "$migration" >/dev/null
}

stage_theme() {
  mkdir -p "$1/.local/state/omarchy/current/theme"
  cat >"$1/.local/state/omarchy/current/theme/opencode.json" <<'EOF'
{"$schema":"https://opencode.ai/theme.json","theme":{"primary":"#336699","secondary":"#00ffff","accent":"#336699","error":"#ff0000","warning":"#ffff00","success":"#00ff00","info":"#0000ff","text":"#ffffff","textMuted":"#111111","background":"#000000","backgroundPanel":"#0d0d0d","backgroundElement":"#171717","backgroundMenu":"#0f0f0f","border":"#2e2e2e","borderActive":"#111111","borderSubtle":"#1f1f1f"}}
EOF
}

# ------------------------------------------------------------------ no opencode config

rm -rf "$test_dir/home"
run_migration

[[ ! -e $test_dir/home/.config/opencode ]] || fail "migration creates an opencode config from nothing"
pass "migration skips installs without an opencode config"

# ------------------------------------------------------------------ existing tui.json

rm -rf "$test_dir/home"
mkdir -p "$test_dir/home/.config/opencode"
printf '{"theme":"tokyonight","keybinds":{"leader":"<c-b>"}}\n' >"$test_dir/home/.config/opencode/tui.json"
stage_theme "$test_dir/home"
run_migration

plugin="$test_dir/home/.config/opencode/tui-plugins/omarchy-theme.ts"
[[ -L $plugin ]] || fail "migration links the omarchy-theme plugin"
pass "migration links the omarchy-theme plugin"
[[ $(readlink "$plugin") == "$plugin_spec" ]] || fail "plugin link points at the shipped plugin"
pass "plugin link points at the shipped plugin"

jq -e --arg plugin "$plugin" \
  '.keybinds.leader == "<c-b>" and (.theme // "omarchy") and (.plugin | index($plugin))' \
  "$test_dir/home/.config/opencode/tui.json" >/dev/null ||
  fail "migration registers the plugin and preserves tui.json settings"
[[ $(jq -r '.theme' "$test_dir/home/.config/opencode/tui.json") == "tokyonight" ]] ||
  fail "migration does not switch the user's theme"
pass "migration registers the plugin and preserves tui.json settings"

run_migration
[[ $(jq '.plugin | length' "$test_dir/home/.config/opencode/tui.json") == "1" ]] ||
  fail "migration does not register the plugin twice"
pass "migration is idempotent"

[[ -f $test_dir/home/.config/opencode/themes/omarchy.json ]] ||
  fail "migration syncs the current theme file"
pass "migration syncs the current theme file"

# ------------------------------------------------------------------ plugin order

rm -rf "$test_dir/home"
mkdir -p "$test_dir/home/.config/opencode"
printf '{"theme":"tokyonight","plugin":["first.ts","second.ts"]}\n' >"$test_dir/home/.config/opencode/tui.json"
run_migration

jq -e --arg plugin "$plugin" '.plugin == ["first.ts", "second.ts", $plugin]' \
  "$test_dir/home/.config/opencode/tui.json" >/dev/null ||
  fail "migration appends the plugin without rewriting existing order"
pass "migration appends the plugin without rewriting existing order"

# ------------------------------------------------------------------ no tui.json

rm -rf "$test_dir/home"
mkdir -p "$test_dir/home/.config/opencode"
stage_theme "$test_dir/home"
run_migration

jq -e --arg plugin "$test_dir/home/.config/opencode/tui-plugins/omarchy-theme.ts" \
  '(.plugin == [$plugin]) and (has("theme") | not)' \
  "$test_dir/home/.config/opencode/tui.json" >/dev/null ||
  fail "migration creates a plugin-only tui.json without a theme"
pass "migration creates a plugin-only tui.json when absent"

# ------------------------------------------------------------------ XDG_CONFIG_HOME

rm -rf "$test_dir/home"
mkdir -p "$test_dir/home/xdg/opencode"
printf '{"theme":"tokyonight"}\n' >"$test_dir/home/xdg/opencode/tui.json"
HOME="$test_dir/home" XDG_CONFIG_HOME="$test_dir/home/xdg" OMARCHY_PATH="$ROOT" PATH="$ROOT/bin:$PATH" \
  env -u OPENCODE_CONFIG_DIR bash -euo pipefail "$migration" >/dev/null

[[ -L $test_dir/home/xdg/opencode/tui-plugins/omarchy-theme.ts ]] ||
  fail "migration follows XDG_CONFIG_HOME for the plugin"
[[ ! -e $test_dir/home/.config/opencode ]] ||
  fail "migration ignores the default tree when XDG_CONFIG_HOME is set"
pass "migration follows XDG_CONFIG_HOME"
jq -e --arg plugin "$test_dir/home/xdg/opencode/tui-plugins/omarchy-theme.ts" \
  '.plugin | index($plugin)' "$test_dir/home/xdg/opencode/tui.json" >/dev/null
pass "migration registers the plugin in the XDG tree"
