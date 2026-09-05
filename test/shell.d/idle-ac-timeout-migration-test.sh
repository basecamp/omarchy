#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command jq

migration="$ROOT/migrations/1787841800.sh"
[[ -f $migration ]] || fail "idle AC timeout migration exists"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
config="$home/.config/omarchy/shell.json"

run_migration() {
  HOME="$home" PATH="$ROOT/bin:$PATH" bash -euo pipefail "$migration" >/dev/null
}

write_config() {
  rm -rf "$home"
  mkdir -p "$home/.config/omarchy"
  printf '%s\n' "$1" >"$config"
}

jq -e '.idle.ac.screensaver == 300 and .idle.ac.lock == 1800' "$ROOT/config/omarchy/shell.json" >/dev/null ||
  fail "shipped config includes the AC idle profile"
pass "shipped config includes the AC idle profile"

write_config '{"version":1,"idle":{"screensaver":150,"lock":300},"plugins":[]}'
run_migration
jq -e '.idle.screensaver == 150 and .idle.lock == 300 and .idle.ac.screensaver == 300 and .idle.ac.lock == 1800' "$config" >/dev/null ||
  fail "migration adds the AC profile to stock idle timings" "$(cat "$config")"
pass "migration adds the AC profile to stock idle timings"

before=$(sha256sum "$config")
run_migration
[[ $before == $(sha256sum "$config") ]] || fail "migration is idempotent" "$(cat "$config")"
pass "migration is idempotent"

write_config '{"version":1,"idle":{"screensaver":150,"lock":300,"ac":{"screensaver":600,"lock":900}}}'
run_migration
jq -e '.idle.ac.screensaver == 600 and .idle.ac.lock == 900' "$config" >/dev/null ||
  fail "migration leaves an existing AC profile alone" "$(cat "$config")"
pass "migration leaves an existing AC profile alone"

write_config '{"version":1,"idle":{"screensaver":600,"lock":900}}'
run_migration
jq -e '.idle.screensaver == 600 and .idle.lock == 900 and (.idle.ac | not)' "$config" >/dev/null ||
  fail "migration leaves customized idle timings alone" "$(cat "$config")"
pass "migration leaves customized idle timings alone"

write_config '{"version":1,"plugins":[]}'
run_migration
jq -e '.idle.ac.screensaver == 300 and .idle.ac.lock == 1800' "$config" >/dev/null ||
  fail "migration adds AC timeouts when idle is omitted" "$(cat "$config")"
pass "migration adds AC timeouts when idle is omitted"
