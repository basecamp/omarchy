#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command systemd-tmpfiles

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

root="$tmpdir/root"
rule="$ROOT/etc/tmpfiles.d/omarchy-uinput.conf"
test_rule="$root/etc/tmpfiles.d/omarchy-uinput.conf"
test_user=$(id -un)
test_group=$(id -gn)
mkdir -p "$root/dev" "$root/etc/tmpfiles.d"
touch "$root/dev/uinput"
chmod 0600 "$root/dev/uinput"

printf '%s:x:%s:%s:test:/tmp:/bin/bash\n' "$test_user" "$(id -u)" "$(id -g)" >"$root/etc/passwd"
printf '%s:x:%s:\n' "$test_group" "$(id -g)" >"$root/etc/group"
sed "s/ root input / $test_user $test_group /" "$rule" >"$test_rule"

systemd-tmpfiles --create --root="$root" "$test_rule"

[[ $(stat -c '%a' "$root/dev/uinput") == "660" ]] ||
  fail "the uinput tmpfiles rule grants group read/write access"
pass "the uinput tmpfiles rule grants group read/write access"

grep -qFx 'z /dev/uinput 0660 root input - -' "$rule" ||
  fail "the uinput tmpfiles rule assigns the input group"
pass "the uinput tmpfiles rule assigns the input group"

migration="$ROOT/migrations/1787983996.sh"
grep -qFx 'sudo systemd-tmpfiles --create /etc/tmpfiles.d/omarchy-uinput.conf' "$migration" ||
  fail "the uinput migration applies the new rule without waiting for reboot"
pass "the uinput migration applies the rule immediately"
