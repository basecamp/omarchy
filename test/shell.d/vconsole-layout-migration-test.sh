#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

migration=$(grep -rl 'Keep non-Latin keyboard layouts out of the initramfs' "$ROOT/migrations" | head -n 1 || true)
[[ -n $migration ]] || fail "non-Latin keyboard layout migration exists"

# /etc/vconsole.conf normally carries only KEYMAP; XKBLAYOUT is written when an
# X11 layout is set explicitly. Migrations run under bash -euo pipefail, so
# reading XKBLAYOUT without a default aborts the runner on every install that
# does not have one, taking every later migration with it.
if ( set -u; unset XKBLAYOUT; : "${XKBLAYOUT%%,*}" ) 2>/dev/null; then
  fail "an unset XKBLAYOUT is what set -u aborts on"
fi
if ! ( set -u; unset XKBLAYOUT; layout=${XKBLAYOUT-}; : "${layout%%,*}" ) 2>/dev/null; then
  fail "defaulting XKBLAYOUT survives set -u"
fi
grep -F 'echo "${XKBLAYOUT-}"' "$migration" >/dev/null ||
  fail "the migration reads XKBLAYOUT with a default"
pass "keyboard layout migration survives a vconsole.conf without XKBLAYOUT"

# The comma strip has to stay: XKBLAYOUT holds a comma-separated list and only
# the first entry decides whether the initramfs can type a Latin passphrase.
grep -F 'layout=${layout%%,*}' "$migration" >/dev/null ||
  fail "the migration still narrows XKBLAYOUT to its first entry"
if ( set -u; layout="ru,us"; layout=${layout%%,*}; [[ $layout == "ru,us" ]] ); then
  fail "the comma strip reduces a layout list to its first entry"
fi
pass "keyboard layout migration still reads only the primary layout"
