#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

migration="$ROOT/migrations/1786801363.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

skills_source="$test_dir/omarchy/default/agents/skills"
mkdir -p "$skills_source/omarchy" "$skills_source/diagnose-crash"

home="$test_dir/home"

run_migration() {
  HOME="$home" OMARCHY_PATH="$test_dir/omarchy" bash -euo pipefail "$migration" >/dev/null
}

seed_home() {
  rm -rf "$home"
  mkdir -p "$home/.codex/skills/.system" "$home/.pi/agent/skills"

  ln -sfn "$skills_source/omarchy" "$home/.codex/skills/omarchy"
  ln -sfn "$skills_source/diagnose-crash" "$home/.codex/skills/diagnose-crash"
  ln -sfn "$skills_source/omarchy" "$home/.pi/agent/skills/omarchy"

  # A skill the user installed themselves, and one they pointed elsewhere.
  mkdir -p "$home/.codex/skills/hand-written" "$test_dir/elsewhere"
  touch "$home/.codex/skills/hand-written/SKILL.md"
  ln -sfn "$test_dir/elsewhere" "$home/.codex/skills/foreign"
}

seed_home
run_migration

[[ ! -e $home/.codex/skills/omarchy && ! -e $home/.codex/skills/diagnose-crash ]] ||
  fail "migration drops the Codex links to Omarchy's skills"
pass "migration drops the Codex links to Omarchy's skills"

[[ -f $home/.codex/skills/hand-written/SKILL.md ]] ||
  fail "migration keeps a hand-written skill"
pass "migration keeps a hand-written skill"

[[ -L $home/.codex/skills/foreign ]] ||
  fail "migration keeps a link pointing outside Omarchy"
pass "migration keeps a link pointing outside Omarchy"

[[ -d $home/.codex/skills/.system ]] ||
  fail "migration keeps Codex's own .system directory"
pass "migration keeps Codex's own .system directory"

[[ ! -e $home/.pi/agent/skills ]] ||
  fail "migration prunes the emptied Pi skills directory"
pass "migration prunes the emptied Pi skills directory"

run_migration
[[ -f $home/.codex/skills/hand-written/SKILL.md && ! -e $home/.pi/agent/skills ]] ||
  fail "migration is idempotent"
pass "migration is idempotent"

# Nothing to do on a machine that never had either directory.
rm -rf "$home"
mkdir -p "$home"
run_migration
pass "migration succeeds when neither directory exists"

# A Pi directory holding something else is left in place rather than pruned.
seed_home
mkdir -p "$home/.pi/agent/skills/keep-me"
run_migration

[[ -d $home/.pi/agent/skills/keep-me ]] ||
  fail "migration leaves a Pi directory that still holds something"
pass "migration leaves a Pi directory that still holds something"
