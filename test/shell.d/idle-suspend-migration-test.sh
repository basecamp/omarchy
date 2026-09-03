#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command jq

migration="$ROOT/migrations/1786881090.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
config="$home/.config/omarchy/shell.json"

run_migration() {
  HOME="$home" bash -euo pipefail "$migration" >/dev/null
}

write_config() {
  mkdir -p "$home/.config/omarchy"
  printf '%s\n' "$1" >"$config"
}

jq -e '.idle.suspend == 900' "$ROOT/config/omarchy/shell.json" >/dev/null ||
  fail "shipped config declares the automatic suspend timeout"
pass "shipped config declares the automatic suspend timeout"

# A customized config from before idle suspend keeps its existing timings and
# receives only the new default.
write_config '{"version":1,"idle":{"screensaver":240,"lock":480},"bar":{"position":"bottom"}}'
run_migration

[[ $(jq -c '.idle' "$config") == '{"screensaver":240,"lock":480,"suspend":900}' ]] ||
  fail "migration adds idle.suspend without changing existing timings" "$(cat "$config")"
[[ $(jq -r '.bar.position' "$config") == "bottom" ]] ||
  fail "migration preserves unrelated shell settings" "$(cat "$config")"
pass "migration adds only the missing suspend timeout"

before=$(sha256sum "$config")
run_migration
[[ $before == $(sha256sum "$config") ]] ||
  fail "migration is idempotent" "$(cat "$config")"
pass "migration is idempotent"

# Any value already chosen by the user wins, including zero.
write_config '{ "version": 1, "idle": { "suspend": 0 } }'
before=$(sha256sum "$config")
run_migration
[[ $before == $(sha256sum "$config") ]] ||
  fail "migration preserves an existing suspend timeout" "$(cat "$config")"
pass "migration preserves an existing suspend timeout"

# A config without an idle block still receives the new canonical setting.
write_config '{"version":1,"bar":{"position":"top"}}'
run_migration
[[ $(jq -r '.idle.suspend' "$config") == "900" ]] ||
  fail "migration creates a missing idle block" "$(cat "$config")"
pass "migration creates a missing idle block"

# Write through symlinks so dotfile-managed configs remain linked.
target="$test_dir/dotfiles-shell.json"
printf '%s\n' '{"version":1,"idle":{"lock":300}}' >"$target"
mkdir -p "$home/.config/omarchy"
ln -sfn "$target" "$config"
run_migration
[[ -L $config ]] || fail "migration preserves a shell.json symlink"
[[ $(jq -r '.idle.suspend' "$target") == "900" ]] ||
  fail "migration updates the symlink target" "$(cat "$target")"
pass "migration preserves a shell.json symlink"

# Missing and malformed configs are user state the migration must not replace.
rm -f "$config" "$target"
run_migration
[[ ! -e $config ]] || fail "migration does not create a missing user config"
pass "migration does not create a missing user config"

write_config '{ not json'
run_migration
[[ $(cat "$config") == '{ not json' ]] ||
  fail "migration leaves an unparsable config untouched" "$(cat "$config")"
pass "migration leaves an unparsable config untouched"
