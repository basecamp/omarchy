#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

# Packaged installs used to call `pacman -Q`, which boots ALPM (~200ms) on every
# fastfetch. Version now reads /var/lib/pacman/local directly; tests drive a
# fake local db so we never need a stubbed pacman.
local_db="$test_tmp/pacman-local"

reset_db() {
  rm -rf "$local_db"
  mkdir -p "$local_db"
}

install_pkg() {
  mkdir -p "$local_db/${1}-${2}"
}

version() {
  OMARCHY_PACMAN_LOCAL="$local_db" \
    OMARCHY_PATH="${1:-/usr/share/omarchy}" \
    "$ROOT/bin/omarchy-version"
}

reset_db
install_pkg omarchy 4.0.0-1
[[ $(version) == "4.0.0-1" ]] || fail "version reports the stable package"
pass "version reports the stable package"

reset_db
install_pkg omarchy-dev 4.0.0-1
[[ $(version) == "4.0.0-1" ]] || fail "version reports the edge package"
pass "version reports the edge package"

# The edge channel installs omarchy-dev. Prefer it when both are present.
reset_db
install_pkg omarchy-dev 4.1.0-1
install_pkg omarchy 4.0.0-1
[[ $(version) == "4.1.0-1" ]] || fail "version prefers the edge package when both are installed"
pass "version prefers the edge package when both are installed"

# omarchy-[0-9]* must not swallow a longer prefix such as omarchy-foo.
reset_db
install_pkg omarchy-foo 9.9.9-1
install_pkg omarchy 4.0.0-1
[[ $(version) == "4.0.0-1" ]] || fail "version ignores similarly prefixed packages"
pass "version ignores similarly prefixed packages"

reset_db
install_pkg omarchy "1:4.0.0-1"
[[ $(version) == "1:4.0.0-1" ]] || fail "version reports an epoch"
pass "version reports an epoch"

# A checkout reports its hash instead, so packages are irrelevant there.
[[ $(version "$test_tmp/checkout") == "dev" ]] || fail "version reports a dev checkout"
pass "version reports a dev checkout"

reset_db
if version >/dev/null 2>&1; then
  fail "version fails when no Omarchy package is installed"
fi
pass "version fails when no Omarchy package is installed"

# The snapshot description is only a label, so a failed lookup must not abort
# the update under set -e.
snapshot_desc=$(
  set -e
  OMARCHY_PACMAN_LOCAL="$local_db" OMARCHY_PATH=/usr/share/omarchy \
    bash -c 'DESC="$('"$ROOT"'/bin/omarchy-version 2>/dev/null || echo unknown)"; echo "$DESC"'
) || fail "snapshot survives an unknown version"

[[ $snapshot_desc == "unknown" ]] || fail "snapshot labels an unknown version" "actual: $snapshot_desc"
pass "snapshot survives an unknown version"
