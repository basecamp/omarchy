#!/bin/bash

set -euo pipefail

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
stub_bin="$tmpdir/bin"
migration_log="$tmpdir/migration.log"
mkdir -p "$stub_bin"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
[[ $1 == "systemd-tmpfiles" ]]
echo "$*" >>"$OMARCHY_TEST_MIGRATION_LOG"
systemd-tmpfiles --create --root="$OMARCHY_TEST_ROOT" "$OMARCHY_TEST_RULE"
SH
chmod +x "$stub_bin/sudo"

run_migration() {
  PATH="$stub_bin:$PATH" \
    OMARCHY_UINPUT_DEVICE="$root/dev/uinput" \
    OMARCHY_UINPUT_RULE="$test_rule" \
    OMARCHY_UINPUT_OWNER="$test_user" \
    OMARCHY_UINPUT_GROUP="$test_group" \
    OMARCHY_TEST_ROOT="$root" \
    OMARCHY_TEST_RULE="$test_rule" \
    OMARCHY_TEST_MIGRATION_LOG="$migration_log" \
    bash -euo pipefail "$migration" >/dev/null
}

rm "$root/dev/uinput"
run_migration
[[ ! -e $migration_log ]] || fail "the uinput migration skips an absent device"
pass "the uinput migration skips an absent device"

touch "$root/dev/uinput"
chmod 0660 "$root/dev/uinput"
run_migration
[[ ! -e $migration_log ]] || fail "the uinput migration skips an already-correct device"
pass "the uinput migration skips an already-correct device"

chmod 0600 "$root/dev/uinput"
run_migration
[[ $(stat -c '%a' "$root/dev/uinput") == "660" ]] ||
  fail "the uinput migration repairs the current device mode"
(( $(wc -l <"$migration_log") == 1 )) ||
  fail "the uinput migration escalates once when repair is needed" "$(cat "$migration_log")"
pass "the uinput migration applies the rule when repair is needed"

run_migration
(( $(wc -l <"$migration_log") == 1 )) ||
  fail "the repaired uinput device avoids another sudo prompt" "$(cat "$migration_log")"
pass "the repaired uinput device avoids another sudo prompt"
