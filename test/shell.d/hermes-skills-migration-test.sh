#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

migration="$ROOT/migrations/1787843905.sh"
[[ -f $migration ]] || fail "Hermes skills migration exists"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
home="$test_dir/home"

run_migration() {
  HOME="$home" OMARCHY_PATH="$ROOT" bash -euo pipefail "$migration" >/dev/null ||
    fail "migration exits clean"
}

assert_link() {
  local link="$1"
  local skill="$2"
  local description="$3"

  [[ -L $link && $(readlink "$link") == "$ROOT/default/agents/skills/$skill" ]] ||
    fail "$description" "$link -> $(readlink "$link" 2>/dev/null || echo missing)"
}

# ------------------------------------------------------------------ default home, no profiles

rm -rf "$home"
mkdir -p "$home"
run_migration

for skill in omarchy diagnose-crash; do
  assert_link "$home/.hermes/skills/$skill" "$skill" "migration links $skill into the default Hermes home"
done
[[ -e $home/.hermes/profiles ]] && fail "migration does not create Hermes profiles"
pass "migration links the default Hermes home and does not create profiles"

run_migration
for skill in omarchy diagnose-crash; do
  assert_link "$home/.hermes/skills/$skill" "$skill" "migration is idempotent on the default home for $skill"
done
pass "migration is idempotent on the default home"

# ------------------------------------------------------------------ pre-existing profile

rm -rf "$home"
mkdir -p "$home/.hermes/profiles/james"
run_migration

for skill in omarchy diagnose-crash; do
  assert_link "$home/.hermes/skills/$skill" "$skill" "migration links $skill into the default Hermes home when a profile exists"
  assert_link "$home/.hermes/profiles/james/skills/$skill" "$skill" "migration links $skill into a pre-existing Hermes profile"
done
[[ -d $home/.hermes/profiles/james ]] || fail "migration leaves the pre-existing profile in place"
profile_count=$(find "$home/.hermes/profiles" -mindepth 1 -maxdepth 1 -type d | wc -l)
(( profile_count == 1 )) || fail "migration does not create extra profiles" "count=$profile_count"
pass "migration links a pre-existing Hermes profile and does not create extras"

run_migration
for skill in omarchy diagnose-crash; do
  assert_link "$home/.hermes/skills/$skill" "$skill" "migration is idempotent on the default home when a profile exists for $skill"
  assert_link "$home/.hermes/profiles/james/skills/$skill" "$skill" "migration is idempotent on a pre-existing profile for $skill"
done
pass "migration is idempotent on a pre-existing profile"

# ------------------------------------------------------------------ missing skill source

rm -rf "$home"
mkdir -p "$home" "$test_dir/empty-omarchy"
HOME="$home" OMARCHY_PATH="$test_dir/empty-omarchy" bash -euo pipefail "$migration" >/dev/null ||
  fail "migration exits clean when the skill source is missing"
[[ -e $home/.hermes ]] && fail "migration no-ops when the skill source is missing"
pass "migration no-ops when the skill source is missing"
