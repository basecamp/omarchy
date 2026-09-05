#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Electron/Obsidian treats a single-dash token as a CLI command, so the shipped
# `-disable-gpu` breaks `obsidian --version`. Complements #8700: that PR is the
# default; this also repairs copies already in ~/.config.

flags_src="$ROOT/config/obsidian/user-flags.conf"
migration=$(grep -l "Fix Obsidian -disable-gpu so CLI commands parse" "$ROOT"/migrations/*.sh | head -1)

grep -qxF -- '--disable-gpu' "$flags_src" ||
  fail "the shipped Obsidian flags use a Chromium double-dash switch"
! grep -qxF -- '-disable-gpu' "$flags_src" ||
  fail "the shipped Obsidian flags do not keep the single-dash typo"
pass "the shipped Obsidian flags use --disable-gpu"

[[ -n $migration ]] || fail "a migration repairs existing ~/.config copies"
[[ ! -x $migration ]] || fail "the migration is not executable"
! grep -q '^#!' "$migration" || fail "the migration has no shebang"
pass "a migration repairs existing ~/.config copies"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
home="$test_tmp/home"
mkdir -p "$home/.config/obsidian"

run_migration() {
  HOME="$home" bash -euo pipefail "$migration" >/dev/null
}

printf '%s\n' '# Obsidian reads this file through the Arch package wrapper.' '-disable-gpu' '--enable-wayland-ime' \
  >"$home/.config/obsidian/user-flags.conf"

run_migration
grep -qxF -- '--disable-gpu' "$home/.config/obsidian/user-flags.conf" ||
  fail "migration turns the shipped typo into --disable-gpu"
! grep -qxF -- '-disable-gpu' "$home/.config/obsidian/user-flags.conf" ||
  fail "migration removes the single-dash typo"
grep -qxF -- '--enable-wayland-ime' "$home/.config/obsidian/user-flags.conf" ||
  fail "migration leaves neighbouring flags alone"
pass "migration turns the shipped typo into --disable-gpu"

before=$(cat "$home/.config/obsidian/user-flags.conf")
run_migration
[[ $(cat "$home/.config/obsidian/user-flags.conf") == "$before" ]] ||
  fail "migration is idempotent"
pass "migration is idempotent"

printf '%s\n' '# -disable-gpu' '--enable-wayland-ime' >"$home/.config/obsidian/user-flags.conf"
run_migration
grep -qxF -- '# -disable-gpu' "$home/.config/obsidian/user-flags.conf" ||
  fail "migration leaves a commented-out flag alone"
pass "migration leaves a commented-out flag alone"

empty_home="$test_tmp/empty-home"
mkdir -p "$empty_home"
HOME="$empty_home" bash -euo pipefail "$migration" >/dev/null ||
  fail "migration succeeds when the user has no Obsidian flags"
pass "migration succeeds when the user has no Obsidian flags"

link_home="$test_tmp/link-home"
mkdir -p "$link_home/.config/obsidian" "$test_tmp/real"
printf '%s\n' '-disable-gpu' >"$test_tmp/real/user-flags.conf"
ln -s "$test_tmp/real/user-flags.conf" "$link_home/.config/obsidian/user-flags.conf"
HOME="$link_home" bash -euo pipefail "$migration" >/dev/null
[[ -L $link_home/.config/obsidian/user-flags.conf ]] ||
  fail "migration leaves a symlink in place"
[[ $(cat "$test_tmp/real/user-flags.conf") == "-disable-gpu" ]] ||
  fail "migration does not rewrite a symlink target"
pass "migration leaves a symlink alone"
