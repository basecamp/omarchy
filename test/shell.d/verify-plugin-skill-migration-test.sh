#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1786714644.sh"
skill="$ROOT/default/agents/skills/verify-plugin"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

home="$test_tmp/home"

run_migration() {
  HOME="$home" OMARCHY_PATH="$ROOT" bash -euo pipefail "$migration" >/dev/null
}

reset_home() {
  rm -rf "$home"
  mkdir -p "$home"
}

# Every agent reads skills from its own directory, so a skill Omarchy ships has
# to land in all of them for a review to find it.
reset_home
run_migration
for skills_dir in .agents/skills .claude/skills .codex/skills .pi/agent/skills; do
  [[ $(readlink "$home/$skills_dir/verify-plugin") == "$skill" ]] ||
    fail "the migration links the skill into $skills_dir" "$(readlink -m "$home/$skills_dir/verify-plugin")"
done
pass "the verify-plugin skill is linked for every agent"

run_migration
[[ $(readlink "$home/.agents/skills/verify-plugin") == "$skill" ]] ||
  fail "running the migration twice keeps the link"
pass "the verify-plugin migration runs twice without complaint"

# A review method of one's own is the whole point of the skill being a file, and
# an update is not an argument for replacing it.
reset_home
mkdir -p "$home/.agents/skills/verify-plugin"
printf 'The review I keep.\n' >"$home/.agents/skills/verify-plugin/SKILL.md"
run_migration
[[ ! -L $home/.agents/skills/verify-plugin ]] ||
  fail "the migration replaces a review folder of one's own"
[[ $(<"$home/.agents/skills/verify-plugin/SKILL.md") == "The review I keep." ]] ||
  fail "the migration rewrites a review folder of one's own"
pass "the migration leaves a review folder of one's own alone"

reset_home
mkdir -p "$home/.agents/skills" "$test_tmp/own-review"
printf 'The review I keep elsewhere.\n' >"$test_tmp/own-review/SKILL.md"
ln -sfn "$test_tmp/own-review" "$home/.agents/skills/verify-plugin"
run_migration
[[ $(readlink "$home/.agents/skills/verify-plugin") == "$test_tmp/own-review" ]] ||
  fail "the migration repoints a link to a review of one's own"
pass "the migration leaves a link to a review of one's own alone"

# A link to nowhere is Omarchy's own, from a checkout that has moved.
reset_home
mkdir -p "$home/.agents/skills"
ln -sfn "$test_tmp/gone" "$home/.agents/skills/verify-plugin"
run_migration
[[ $(readlink "$home/.agents/skills/verify-plugin") == "$skill" ]] ||
  fail "the migration repairs a link to nowhere"
pass "the migration repairs a link to nowhere"

# Rewriting a link that is already right is how a directory nobody can write to
# turns into a migration that never finishes.
reset_home
run_migration
chmod 500 "$home/.agents/skills"
run_migration || fail "a read-only skills directory fails a migration with nothing left to do"
chmod 700 "$home/.agents/skills"
pass "the migration asks nothing of a directory it has already linked"
