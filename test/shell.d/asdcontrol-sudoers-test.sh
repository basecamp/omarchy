#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

sudoers_file="$ROOT/etc/sudoers.d/omarchy-asdcontrol"
wrapper="$ROOT/bin/omarchy-brightness-display-apple"
hook="$ROOT/etc/pacman.d/hooks/omarchy-asdcontrol-sudoers.hook"

rules=$(grep -vE '^[[:space:]]*(#|$)' "$sudoers_file")
[[ $rules == *'(root) NOPASSWD:'* ]] ||
  fail "asdcontrol sudoers runs as root, not ALL" "got: $rules"

! grep -Eq 'NOPASSWD:[[:space:]]*/usr/bin/asdcontrol[[:space:]]*$' "$sudoers_file" ||
  fail "asdcontrol sudoers does not grant any arguments"

! grep -F '*' "$sudoers_file" >/dev/null ||
  fail "asdcontrol sudoers does not use a wildcard that admits extra arguments"

! grep -vE '^[[:space:]]*(#|$)' "$sudoers_file" | grep -F -- '--force' >/dev/null ||
  fail "asdcontrol sudoers does not admit --force"

if command -v visudo >/dev/null; then
  visudo -cf "$sudoers_file" >/dev/null || fail "asdcontrol sudoers rule parses"
fi

grep -F 'sudo asdcontrol --detect "${devices[@]}"' "$wrapper" >/dev/null ||
  fail "brightness wrapper detects with passwordless --detect"

grep -F 'sudo asdcontrol "$device"' "$wrapper" >/dev/null ||
  fail "brightness wrapper reads brightness with a hiddev path"

grep -F 'sudo asdcontrol "$device" -- "$step"' "$wrapper" >/dev/null ||
  fail "brightness wrapper sets brightness as hiddev -- step"

grep -F 'Exec = /usr/bin/rm -f /etc/sudoers.d/asdcontrol' "$hook" >/dev/null ||
  fail "pacman hook removes the unconstrained asdcontrol sudoers file"

pass "asdcontrol sudoers is scoped to hiddev detect/get/set"
