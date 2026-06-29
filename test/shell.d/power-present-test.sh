#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

write_supply() {
  local name="$1"
  local type="$2"
  local online="$3"

  mkdir -p "$tmp_dir/$name"
  printf '%s\n' "$type" >"$tmp_dir/$name/type"
  printf '%s\n' "$online" >"$tmp_dir/$name/online"
}

write_supply AC Mains 0
write_supply USBC USB 1

OMARCHY_POWER_SUPPLY_PATH="$tmp_dir" "$ROOT/bin/omarchy-power-present" ||
  fail "power present detects online USB-C supply"
pass "power present detects online USB-C supply"

printf '0\n' >"$tmp_dir/USBC/online"

if OMARCHY_POWER_SUPPLY_PATH="$tmp_dir" "$ROOT/bin/omarchy-power-present"; then
  fail "power present rejects offline supplies"
fi
pass "power present rejects offline supplies"

write_supply AC Mains 1

OMARCHY_POWER_SUPPLY_PATH="$tmp_dir" "$ROOT/bin/omarchy-power-present" ||
  fail "power present detects online mains supply"
pass "power present detects online mains supply"
