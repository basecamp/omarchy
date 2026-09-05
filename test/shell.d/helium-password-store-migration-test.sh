#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

migration="$ROOT/migrations/1788439900.sh"
[[ -f $migration ]] || fail "Helium password-store migration exists"

default_flags="$ROOT/config/helium-browser-flags.conf"
[[ -f $default_flags ]] || fail "fresh installs pin Helium's password store"
[[ $(<"$default_flags") == "--password-store=gnome-libsecret" ]] ||
  fail "fresh installs pin Helium's password store"
pass "fresh installs pin Helium's password store"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

run_migration() {
  local home=$1

  HOME="$home" bash -euo pipefail "$migration" >/dev/null
}

home="$test_dir/commented-option"
mkdir -p "$home/.config"
printf '%s\n' '# --password-store=basic' >"$home/.config/helium-browser-flags.conf"

run_migration "$home"

[[ $(<"$home/.config/helium-browser-flags.conf") == $'# --password-store=basic\n--password-store=gnome-libsecret' ]] ||
  fail "migration ignores a commented password-store option"
pass "migration ignores a commented password-store option"

home="$test_dir/existing-user"
mkdir -p "$home"

run_migration "$home" || fail "migration prepares existing users for a future Helium install"

grep -qxF -- '--password-store=gnome-libsecret' "$home/.config/helium-browser-flags.conf" ||
  fail "migration prepares existing users for a future Helium install"
pass "migration prepares existing users for a future Helium install"

home="$test_dir/custom-option"
mkdir -p "$home/.config"
printf '%s\n' '--password-store=basic' >"$home/.config/helium-browser-flags.conf"

run_migration "$home"

[[ $(<"$home/.config/helium-browser-flags.conf") == "--password-store=basic" ]] ||
  fail "migration preserves an active password-store choice"
pass "migration preserves an active password-store choice"

home="$test_dir/missing-newline"
mkdir -p "$home/.config"
printf %s '--ozone-platform=wayland' >"$home/.config/helium-browser-flags.conf"

run_migration "$home"

[[ $(<"$home/.config/helium-browser-flags.conf") == $'--ozone-platform=wayland\n--password-store=gnome-libsecret' ]] ||
  fail "migration appends the pin on its own line"
pass "migration appends the pin on its own line"

before=$(sha256sum "$home/.config/helium-browser-flags.conf")
run_migration "$home"
after=$(sha256sum "$home/.config/helium-browser-flags.conf")

[[ $before == "$after" ]] || fail "Helium password-store migration is idempotent"
pass "Helium password-store migration is idempotent"
