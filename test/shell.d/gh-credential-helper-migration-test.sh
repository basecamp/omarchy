#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

migration=$(grep -rl 'Point GitHub credential helpers at a stable mise gh invocation' "$ROOT/migrations" | head -n 1 || true)
[[ -n $migration ]] || fail "gh credential helper migration exists"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

cfg="$TMPDIR/gitconfig"
export GIT_CONFIG_GLOBAL="$cfg"
export GIT_CONFIG_SYSTEM=/dev/null
: >"$cfg"

# Migrations run with OMARCHY_PATH/bin on PATH; keep that for omarchy-cmd-present.
export PATH="$ROOT/bin:$PATH"
export OMARCHY_PATH="$ROOT"

good='!mise exec --quiet gh -- gh auth git-credential'
versioned='!/home/u/.local/share/mise/installs/gh/2.97.0/gh_2.97.0_linux_amd64/bin/gh auth git-credential'
wrapper='!/home/u/.local/bin/gh auth git-credential'

run_migration() {
  bash -euo pipefail "$migration" >/dev/null || fail "migration exits clean"
}

git config --global credential.https://github.com.helper "$versioned"
git config --global --add credential.https://github.com.helper ''
git config --global credential.https://gist.github.com.helper "$wrapper"
git config --global credential.helper store

run_migration

git config --global --get-all credential.https://github.com.helper | grep -Fxq "$good" ||
  fail "github helper rewritten to mise exec"
git config --global --get-all credential.https://github.com.helper | grep -Fq 'mise/installs/gh/' &&
  fail "versioned github helper removed"
# Empty values are a blank line from --get-all; check before capturing into a var
# (command substitution strips a trailing empty line).
git config --global --get-all credential.https://github.com.helper | grep -Fxq '' ||
  fail "empty github helper entry preserved"
git config --global --get-all credential.https://gist.github.com.helper | grep -Fxq "$good" ||
  fail "gist helper rewritten to mise exec"
git config --global --get-all credential.https://gist.github.com.helper | grep -Fq '.local/bin/gh' &&
  fail "wrapper gist helper removed"
[[ $(git config --global --get credential.helper) == store ]] || fail "unrelated credential.helper untouched"
pass "migration rewrites only broken GitHub and Gist helpers"

# Already-good values must not be duplicated on a second run.
run_migration
github_count=$(git config --global --get-all credential.https://github.com.helper | grep -Fxc "$good")
gist_count=$(git config --global --get-all credential.https://gist.github.com.helper | grep -Fxc "$good")
(( github_count == 1 )) || fail "idempotent: one good github helper ($github_count)"
(( gist_count == 1 )) || fail "idempotent: one good gist helper ($gist_count)"
pass "migration is idempotent when helpers are already fixed"
