#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1788200002.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
mkdir -p "$stub_bin"

cat >"$stub_bin/omarchy-hw-apple-silicon" <<'SH'
#!/bin/bash

[[ ${APPLE_SILICON:-0} == "1" ]]
SH

# Stubbed rather than run: the real one would install a package.
cat >"$stub_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash

printf 'omarchy-pkg-add %s\n' "$*" >>"$TEST_LOG"
SH

chmod +x "$stub_bin"/*

# omarchy-migrate runs migrations under bash -euo pipefail.
run_migration() {
  local apple_silicon="${1:-1}"

  : >"$calls"

  APPLE_SILICON="$apple_silicon" TEST_LOG="$calls" PATH="$stub_bin:$PATH" \
    bash -euo pipefail "$migration" >/dev/null
}

run_migration
grep -Fxq 'omarchy-pkg-add rtkit' "$calls" ||
  fail "the migration installs rtkit on Apple Silicon" "$(cat "$calls")"
pass "the migration installs rtkit on Apple Silicon"

# omarchy-pkg-add installs with --needed, so a second run asks for the same
# package and changes nothing.
run_migration
(( $(grep -Fxc 'omarchy-pkg-add rtkit' "$calls") == 1 )) ||
  fail "the migration is idempotent" "$(cat "$calls")"
pass "the migration is idempotent"

# The x86_64 package set already carries rtkit; nothing else needs the install.
run_migration 0
[[ ! -s $calls ]] ||
  fail "the migration leaves other hardware alone" "$(cat "$calls")"
pass "the migration is scoped to Apple Silicon"
