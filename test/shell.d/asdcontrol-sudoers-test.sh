#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

sudoers_file="$ROOT/etc/sudoers.d/omarchy-asdcontrol"
wrapper="$ROOT/bin/omarchy-brightness-display-apple"
hook="$ROOT/etc/pacman.d/hooks/omarchy-asdcontrol-sudoers.hook"

expected='%wheel ALL=(root) NOPASSWD: /usr/bin/asdcontrol ^--detect( /dev/(usb/)?hiddev[0-9]+)+$
%wheel ALL=(root) NOPASSWD: /usr/bin/asdcontrol ^/dev/(usb/)?hiddev[0-9]+$
%wheel ALL=(root) NOPASSWD: /usr/bin/asdcontrol ^/dev/(usb/)?hiddev[0-9]+ -- [+-]?[0-9]+%$'

rules=$(grep -vE '^[[:space:]]*(#|$)' "$sudoers_file")
[[ $rules == "$expected" ]] ||
  fail "asdcontrol sudoers is the three hiddev detect/get/set rules" "got: $rules"

eres=()
while IFS= read -r line; do
  [[ $line =~ /usr/bin/asdcontrol[[:space:]]+(.*)$ ]] ||
    fail "asdcontrol sudoers rule is a command ERE" "got: $line"
  eres+=("${BASH_REMATCH[1]}")
done <<<"$rules"

(( ${#eres[@]} == 3 )) ||
  fail "asdcontrol sudoers has three command EREs" "got ${#eres[@]}"

granted() {
  local args=$1
  local ere
  for ere in "${eres[@]}"; do
    grep -Eq -- "$ere" <<<"$args" && return 0
  done
  return 1
}

must_grant() {
  if ! granted "$1"; then
    fail "sudoers ERE grants '$1'"
  fi
}

must_deny() {
  if granted "$1"; then
    fail "sudoers ERE rejects '$1'"
  fi
}

must_grant "--detect /dev/usb/hiddev0"
must_grant "--detect /dev/hiddev0"
must_grant "--detect /dev/usb/hiddev0 /dev/hiddev1"
must_grant "/dev/usb/hiddev0"
must_grant "/dev/hiddev0"
must_grant "/dev/usb/hiddev0 -- +5%"
must_grant "/dev/hiddev0 -- -10%"
must_grant "/dev/usb/hiddev0 -- 50%"

must_deny "--force /dev/usb/hiddev0"
must_deny "--detect /dev/sda"
must_deny "--detect /tmp/hiddev0"
must_deny "--detect"
must_deny "/dev/sda"
must_deny "/dev/usb/hiddev0 extra"
must_deny "/dev/usb/hiddev0 -- +5% extra"
must_deny "/dev/usb/hiddev0 -- 50"
must_deny "--detect /dev/usb/hiddev0 --force"
must_deny "/dev/usb/hiddev0 -- --force"

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
