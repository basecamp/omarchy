#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1787566169.sh"
[[ -f $migration ]] || fail "Ghostty working-directory migration exists"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

run_migration() {
  local home=$1
  local cache_home=$2

  HOME="$home" XDG_CACHE_HOME="$cache_home" OMARCHY_PATH="$ROOT" \
    bash -euo pipefail "$migration" >/dev/null
}

existing_home="$test_tmp/existing-home"
existing_config="$existing_home/.config/ghostty/config"
existing_desktop="$existing_home/.local/share/applications/com.mitchellh.ghostty.desktop"
existing_cache="$existing_home/custom-cache"

mkdir -p "$(dirname "$existing_config")" "$existing_cache"
printf '%s\n' \
  '# Window' \
  'window-theme = ghostty' >"$existing_config"
touch "$existing_cache/xdg-terminal-exec"

run_migration "$existing_home" "$existing_cache"

[[ $(grep -cE '^[[:space:]]*gtk-single-instance[[:space:]]*=[[:space:]]*false[[:space:]]*$' "$existing_config") == 1 ]] ||
  fail "migration adds the multi-process default to an existing Ghostty config"
cmp -s "$ROOT/default/ghostty/com.mitchellh.ghostty.desktop" "$existing_desktop" ||
  fail "migration installs Omarchy's Ghostty desktop entry"
[[ ! -e $existing_cache/xdg-terminal-exec ]] ||
  fail "migration invalidates the xdg-terminal-exec cache"
pass "migration applies the Ghostty working-directory defaults"

before=$(sha256sum "$existing_config" "$existing_desktop")
run_migration "$existing_home" "$existing_cache"
after=$(sha256sum "$existing_config" "$existing_desktop")
[[ $before == "$after" ]] || fail "Ghostty working-directory migration is idempotent"
pass "Ghostty working-directory migration is idempotent"

custom_home="$test_tmp/custom-home"
custom_config="$custom_home/.config/ghostty/config"
custom_desktop="$custom_home/.local/share/applications/com.mitchellh.ghostty.desktop"
custom_cache="$custom_home/custom-cache"

mkdir -p "$(dirname "$custom_config")" "$(dirname "$custom_desktop")" "$custom_cache"
printf '%s\n' \
  '# User requires shared Ghostty windows' \
  'gtk-single-instance = true' >"$custom_config"
printf '%s\n' \
  '[Desktop Entry]' \
  'Name=Custom Ghostty' \
  'Exec=/usr/bin/ghostty --custom' >"$custom_desktop"
touch "$custom_cache/xdg-terminal-exec"

custom_before=$(sha256sum "$custom_config" "$custom_desktop")
run_migration "$custom_home" "$custom_cache"
custom_after=$(sha256sum "$custom_config" "$custom_desktop")

[[ $custom_before == "$custom_after" ]] ||
  fail "migration preserves explicit Ghostty settings and desktop overrides"
[[ ! -e $custom_cache/xdg-terminal-exec ]] ||
  fail "migration invalidates the cache while preserving Ghostty customizations"
pass "migration preserves explicit Ghostty customizations"

unused_home="$test_tmp/unused-home"
unused_cache="$unused_home/custom-cache"
mkdir -p "$unused_cache"
touch "$unused_cache/xdg-terminal-exec"

run_migration "$unused_home" "$unused_cache"

[[ ! -e $unused_home/.config/ghostty ]] ||
  fail "migration does not create a Ghostty config for users without one"
[[ ! -e $unused_home/.local/share/applications/com.mitchellh.ghostty.desktop ]] ||
  fail "migration does not install a Ghostty desktop entry for users without a config"
[[ -e $unused_cache/xdg-terminal-exec ]] ||
  fail "migration leaves unrelated xdg-terminal-exec state alone"
pass "migration leaves users without Ghostty configuration unchanged"
