#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

qs_swap="$ROOT/migrations/1787399318.sh"
qt_align="$ROOT/migrations/1787514500.sh"

[[ -f $qs_swap ]] || fail "upstream packaged-quickshell migration is present"
[[ -f $qt_align ]] || fail "Qt ABI companion migration is present"

grep -Fq 'pacman -S --noconfirm --ask 4 quickshell' "$qs_swap" \
  || fail "1787399318 still installs packaged quickshell"
if grep -Eq 'pacman -S .*quickshell-git' "$qs_swap"; then
  fail "1787399318 must not be rewritten to install quickshell-git"
fi

grep -Fq 'Do not undo 1787399318' "$qt_align" \
  || fail "companion says it will not undo the packaged quickshell swap"
if grep -Eq 'pacman -S .*quickshell-git' "$qt_align"; then
  fail "companion must not reinstall quickshell-git"
fi
grep -Fq 'qt6-base' "$qt_align" \
  || fail "companion upgrades qt6-base to match packaged quickshell"
grep -Fq 'QUntypedPropertyBindingC1EP23QPropertyBindingPrivate@@Qt_6' "$qt_align" \
  || fail "companion no-ops once the public Qt_6 ctor exists"
grep -Fq '[[ $(nm -D /usr/lib/libQt6Core.so.6) ==' "$qt_align" \
  || fail "companion must not use nm|grep -q under migrate pipefail"

# Later stamp so it cannot run before the swap it is repairing.
qs_stamp=${qs_swap##*/}
qs_stamp=${qs_stamp%.sh}
qt_stamp=${qt_align##*/}
qt_stamp=${qt_stamp%.sh}
if (( qt_stamp <= qs_stamp )); then
  fail "Qt ABI companion stamp is after 1787399318"
fi

pass "packaged quickshell stays; Qt is aligned to its ABI"
