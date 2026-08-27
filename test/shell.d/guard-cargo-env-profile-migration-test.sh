#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

migration="$ROOT/migrations/1787867690.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
mkdir -p "$home"

unguarded_dot='. "$HOME/.cargo/env"'
unguarded_source='source "$HOME/.cargo/env"'
guarded='[[ -r "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"'
custom='export EDITOR=nvim'

run_migration() {
  HOME="$home" bash -euo pipefail "$migration" >/dev/null
}

# ~/.profile with rustup's unguarded line: rewritten.
printf '%s\n' "$unguarded_dot" >"$home/.profile"
run_migration || fail "migration runs against an unguarded .profile"
grep -qxF -- "$guarded" "$home/.profile" || fail "migration guards the rustup .profile line" "actual: $(cat "$home/.profile")"
grep -qxF -- "$unguarded_dot" "$home/.profile" && fail "migration must remove the unguarded .profile line"
pass "migration guards an unguarded .profile cargo env line"

# Idempotent when already guarded.
before=$(cat "$home/.profile")
run_migration || fail "migration is idempotent on a guarded .profile"
[[ $(cat "$home/.profile") == "$before" ]] || fail "migration must not rewrite an already-guarded .profile"
pass "migration is a no-op when .profile is already guarded"

# source form in .bashrc, leave unrelated lines alone.
printf '%s\n' "$custom" "$unguarded_source" >"$home/.bashrc"
run_migration || fail "migration runs against .bashrc"
grep -qxF -- "$custom" "$home/.bashrc" || fail "migration preserves unrelated .bashrc lines"
grep -qxF -- "$guarded" "$home/.bashrc" || fail "migration guards the source form in .bashrc"
grep -qxF -- "$unguarded_source" "$home/.bashrc" && fail "migration must remove the unguarded source line"
pass "migration guards source \"\$HOME/.cargo/env\" in .bashrc and keeps other lines"

# Custom profile with no rustup line: untouched.
printf '%s\n' "$custom" >"$home/.zprofile"
run_migration || fail "migration runs when no cargo env line is present"
grep -qxF -- "$custom" "$home/.zprofile" || fail "migration must leave unrelated profiles alone"
grep -q 'cargo/env' "$home/.zprofile" && fail "migration must not invent a cargo env line"
pass "migration leaves profiles without a rustup cargo env line alone"

# Missing files: no-op.
rm -f "$home/.bash_profile" "$home/.zshrc"
run_migration || fail "migration tolerates missing profile files"
[[ ! -e $home/.bash_profile ]] || fail "migration must not create missing profile files"
pass "migration no-ops for missing profile files"
