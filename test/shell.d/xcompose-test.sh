#!/bin/bash

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

cedilla='<dead_acute> <c> : "ç" ccedilla'

# $1 names the home to write into, $2 the vconsole.conf to read the keyboard
# choice from; omitting it stands in for a machine without the file.
run_xcompose() {
  local home="$test_tmp/$1"

  mkdir -p "$home"
  HOME="$home" \
    OMARCHY_USER_NAME="Ada Lovelace" \
    OMARCHY_USER_EMAIL="ada@example.com" \
    OMARCHY_VCONSOLE_CONFIG="${2:-$test_tmp/absent.conf}" \
    bash "$ROOT/install/user/xcompose.sh"
}

printf 'KEYMAP=us-acentos\nXKBLAYOUT=us\nXKBVARIANT=intl\n' >"$test_tmp/intl.conf"
printf 'KEYMAP=de\nXKBLAYOUT=de\n' >"$test_tmp/de.conf"

run_xcompose intl "$test_tmp/intl.conf"
grep -Fx "$cedilla" "$test_tmp/intl/.XCompose" >/dev/null ||
  fail "US International seeds the cedilla override"
grep -F 'Ada Lovelace' "$test_tmp/intl/.XCompose" >/dev/null ||
  fail "seeding the cedilla override keeps the identification sequences"

# The file is rewritten from scratch on every run, so a re-provision must not
# leave the overrides in twice.
run_xcompose intl "$test_tmp/intl.conf"
(($(grep -Fxc "$cedilla" "$test_tmp/intl/.XCompose") == 1)) ||
  fail "re-running the setup does not duplicate the cedilla override"

run_xcompose de "$test_tmp/de.conf"
grep -F ccedilla "$test_tmp/de/.XCompose" >/dev/null &&
  fail "a layout other than US International is left alone"

run_xcompose absent
grep -F ccedilla "$test_tmp/absent/.XCompose" >/dev/null &&
  fail "a machine without a vconsole.conf is left alone"

pass "xcompose setup adds the cedilla override for US International only"
