#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

shipped_migration="$ROOT/migrations/1788102906.sh"
[[ -f $shipped_migration ]] || fail "the legacy power udev rule migration exists at $shipped_migration"

mapfile -t legacy_rule_migrations < <(grep -RIlE '99-(power-profile|wifi-powersave)' "$ROOT/migrations")
(( ${#legacy_rule_migrations[@]} == 1 )) && [[ ${legacy_rule_migrations[0]} == "$shipped_migration" ]] ||
  fail "one migration exclusively owns both legacy udev rule filenames" "${legacy_rule_migrations[*]}"
pass "one migration exclusively owns both legacy udev rule filenames"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/bin"

# sudo runs the real command, so the removals act on the redirected rules
# directory below and the elevated calls land in the log beside it.
cat >"$test_dir/bin/sudo" <<'STUB'
#!/bin/bash

printf 'sudo %s\n' "$*" >>"$CALLS"
if [[ ${1:-} == "/usr/bin/udevadm" ]]; then
  shift
  exec "$UDEVADM_STUB" "$@"
fi
exec "$@"
STUB

cat >"$test_dir/bin/udevadm" <<'STUB'
#!/bin/bash

printf 'udevadm %s\n' "$*" >>"$CALLS"
if [[ -n ${FAIL_UDEV_RELOAD_ONCE_MARKER:-} && ! -e $FAIL_UDEV_RELOAD_ONCE_MARKER ]]; then
  touch "$FAIL_UDEV_RELOAD_ONCE_MARKER"
  exit 1
fi
STUB

cat >"$test_dir/bin/install" <<'STUB'
#!/bin/bash

echo "migration resolved install through PATH" >&2
exit 97
STUB

cat >"$test_dir/bin/rm" <<'STUB'
#!/bin/bash

echo "migration resolved rm through PATH" >&2
exit 98
STUB

cat >"$test_dir/bin/mv" <<'STUB'
#!/bin/bash

echo "migration resolved mv through PATH" >&2
exit 99
STUB

cat >"$test_dir/bin/omarchy-restart-xcompose" <<'STUB'
#!/bin/bash

echo "omarchy-restart-xcompose" >>"$CALLS"
STUB

chmod +x "$test_dir/bin/"*

mkdir -p "$test_dir/failing-bin"
cat >"$test_dir/failing-bin/sudo" <<'STUB'
#!/bin/bash

echo "sudo: a terminal is required to read the password" >&2
exit 1
STUB
chmod +x "$test_dir/failing-bin/sudo"

export CALLS="$test_dir/calls"
export UDEVADM_STUB="$test_dir/bin/udevadm"

rules_dir="$test_dir/rules.d"
home_dir="$test_dir/home"
omarchy_path="$test_dir/omarchy"
xcompose="$home_dir/.XCompose"
packaged_xcompose="include \"$omarchy_path/default/xcompose\""
power_rule="$rules_dir/99-power-profile.rules"
wifi_rule="$rules_dir/99-wifi-powersave.rules"
reload_marker_prefix="$test_dir/reload-needed"
power_reload_marker="$reload_marker_prefix-99-power-profile.rules"
wifi_reload_marker="$reload_marker_prefix-99-wifi-powersave.rules"
udev_control="$test_dir/udev-control"
migration="$test_dir/migration.sh"

# These paths become operands to privileged commands. Keep them fixed in the
# shipped migration and retarget a scratch copy for the unprivileged test; an
# environment override would let the caller choose what root removes.
grep -Fxq 'rules_dir=/etc/udev/rules.d' "$shipped_migration" ||
  fail "the production udev rules directory is a fixed literal"
grep -Fxq 'reload_marker_prefix=/var/lib/omarchy/migrations/1788102906-udev-reload-needed' "$shipped_migration" ||
  fail "the production reload marker is a fixed literal"
grep -Fxq 'udev_control=/run/udev/control' "$shipped_migration" ||
  fail "the production udev control path is a fixed literal"
if grep -q 'OMARCHY_UDEV_' "$shipped_migration"; then
  fail "the migration does not accept caller-controlled privileged paths"
fi

sed \
  -e "s|^rules_dir=/etc/udev/rules.d$|rules_dir=$rules_dir|" \
  -e "s|^reload_marker_prefix=/var/lib/omarchy/migrations/1788102906-udev-reload-needed$|reload_marker_prefix=$reload_marker_prefix|" \
  -e "s|^udev_control=/run/udev/control$|udev_control=$udev_control|" \
  "$shipped_migration" >"$migration"
pass "migration keeps privileged production paths caller-independent"

reset_machine() {
  rm -rf "$rules_dir" "$home_dir" "$omarchy_path" "$power_reload_marker" "$wifi_reload_marker" "$udev_control"
  mkdir -p "$rules_dir" "$home_dir" "$omarchy_path/default"
  touch "$omarchy_path/default/xcompose"
  touch "$udev_control"
}

run_migration() {
  : >"$CALLS"

  HOME="$home_dir" \
    OMARCHY_PATH="$omarchy_path" \
    PATH="$test_dir/bin:$PATH" \
    bash -euo pipefail "$migration" >/dev/null
}

reload_count() {
  grep -cx 'udevadm control --reload' "$CALLS" || true
}

write_xcompose() {
  local include="$1"

  cat >"$xcompose" <<EOF
# Include fast emoji access
$include

# Keep the user's own sequences
<Multi_key> <space> <n> : "Test User"
<Multi_key> <space> <e> : "test@example.com"
EOF
}

# #8175's non-udev behavior belongs here so one migration owns the whole legacy
# compatibility-link repair. Omarchy 3 emitted %H, while users may have changed
# it to ~ or its expanded value.
for legacy_include in \
  'include "%H/.local/share/omarchy/default/xcompose"' \
  'include "~/.local/share/omarchy/default/xcompose"' \
  "include \"$home_dir/.local/share/omarchy/default/xcompose\""; do
  reset_machine
  write_xcompose "$legacy_include"
  run_migration

  grep -qxF "$packaged_xcompose" "$xcompose" ||
    fail "migration repoints $legacy_include at the active Omarchy tree" "$(cat "$xcompose")"
  grep -qF '<Multi_key> <space> <e> : "test@example.com"' "$xcompose" ||
    fail "migration discards the user's own compose sequences"
  grep -qxF 'omarchy-restart-xcompose' "$CALLS" ||
    fail "migration does not reload XCompose after rewriting its include" "$(cat "$CALLS")"
done
pass "migration repoints every legacy XCompose include and preserves custom sequences"

before=$(sha256sum "$xcompose")
run_migration
[[ $(sha256sum "$xcompose") == "$before" ]] || fail "migration changes an already repaired XCompose file"
[[ ! -s $CALLS ]] || fail "migration restarts XCompose when nothing changed" "$(cat "$CALLS")"
pass "migration is idempotent on an already repaired XCompose file"

reset_machine
run_migration
[[ ! -e $xcompose ]] || fail "migration creates a missing XCompose file"
[[ ! -s $CALLS ]] || fail "migration acts when XCompose and legacy udev rules are absent" "$(cat "$CALLS")"
pass "migration leaves a home without XCompose alone"

# What Omarchy 3's unquoted heredoc actually left on disk: the installing user's
# home expanded into a rule root runs on every power_supply event.
write_vulnerable_power_rule() {
  cat >"$power_rule" <<'RULE'
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile --property=After=power-profiles-daemon.service /home/someuser/.local/share/omarchy/bin/omarchy-powerprofiles-set"
SUBSYSTEM=="power_supply", ATTR{type}=="USB", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile --property=After=power-profiles-daemon.service /home/someuser/.local/share/omarchy/bin/omarchy-powerprofiles-set"
RULE
}

write_initial_vulnerable_power_rule() {
  cat >"$power_rule" <<'RULE'
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile-battery --property=After=power-profiles-daemon.service /home/someuser/.local/share/omarchy/bin/omarchy-powerprofiles-set battery"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile-ac --property=After=power-profiles-daemon.service /home/someuser/.local/share/omarchy/bin/omarchy-powerprofiles-set ac"
RULE
}

write_final_vulnerable_power_rule() {
  cat >"$power_rule" <<'RULE'
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="/usr/bin/systemd-run --no-block --collect --property=After=power-profiles-daemon.service /home/someuser/.local/share/omarchy/bin/omarchy-powerprofiles-set"
SUBSYSTEM=="power_supply", ATTR{type}=="USB", RUN+="/usr/bin/systemd-run --no-block --collect --property=After=power-profiles-daemon.service /home/someuser/.local/share/omarchy/bin/omarchy-powerprofiles-set"
RULE
}

write_vulnerable_wifi_rule() {
  cat >"$wifi_rule" <<'RULE'
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="/home/someuser/.local/share/omarchy/bin/omarchy-wifi-powersave on"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="/home/someuser/.local/share/omarchy/bin/omarchy-wifi-powersave off"
RULE
}

write_systemd_vulnerable_wifi_rule() {
  cat >"$wifi_rule" <<'RULE'
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-wifi-powersave-on /home/someuser/.local/share/omarchy/bin/omarchy-wifi-powersave on"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-wifi-powersave-off /home/someuser/.local/share/omarchy/bin/omarchy-wifi-powersave off"
RULE
}

reset_machine
write_vulnerable_power_rule
run_migration

[[ ! -e $power_rule ]] ||
  fail "migration removes a power profile rule that runs out of a user home" "$(cat "$power_rule")"
pass "migration removes a power profile rule that runs out of a user home"

grep -q '^sudo /usr/bin/rm -f .*99-power-profile\.rules$' "$CALLS" ||
  fail "migration removes the rule with elevated privileges" "$(cat "$CALLS")"
pass "migration removes the rule with elevated privileges"

grep -q '^sudo /usr/bin/install -Dm644 /dev/null ' "$CALLS" &&
  grep -q '^sudo /usr/bin/udevadm control --reload$' "$CALLS" ||
  fail "migration pins privileged helpers to root-owned paths" "$(cat "$CALLS")"
pass "migration pins install, rm, and udevadm to root-owned paths"

reset_machine
write_initial_vulnerable_power_rule
run_migration

[[ ! -e $power_rule ]] ||
  fail "migration removes the initial AC/battery power rule" "$(cat "$power_rule")"
(( $(reload_count) == 1 )) ||
  fail "migration reloads udev after removing the initial power rule" "$(cat "$CALLS")"
pass "migration removes the initial AC/battery power rule body"

reset_machine
write_final_vulnerable_power_rule
run_migration

[[ ! -e $power_rule ]] ||
  fail "migration removes the final Omarchy 3 power rule" "$(cat "$power_rule")"
(( $(reload_count) == 1 )) ||
  fail "migration reloads udev after removing the final power rule" "$(cat "$CALLS")"
pass "migration removes the final Omarchy 3 power rule body"

reset_machine
write_vulnerable_wifi_rule
run_migration

[[ ! -e $wifi_rule ]] ||
  fail "migration removes a Wi-Fi power save rule that runs out of a user home" "$(cat "$wifi_rule")"
pass "migration removes a Wi-Fi power save rule that runs out of a user home"

reset_machine
write_systemd_vulnerable_wifi_rule
run_migration

[[ ! -e $wifi_rule ]] ||
  fail "migration removes the systemd-run Wi-Fi rule" "$(cat "$wifi_rule")"
(( $(reload_count) == 1 )) ||
  fail "migration reloads udev after removing the systemd-run Wi-Fi rule" "$(cat "$CALLS")"
pass "migration removes the systemd-run Wi-Fi rule body"

# udevd keeps running the rule it already parsed, so the file being gone from
# disk is only half the fix until it reloads.
(( $(reload_count) == 1 )) ||
  fail "migration reloads udev after removing a rule" "$(cat "$CALLS")"
pass "migration reloads udev after removing a rule"

# Reload each removed rule immediately, so a later failure cannot leave an
# already-deleted rule active in udevd.
reset_machine
write_vulnerable_power_rule
write_vulnerable_wifi_rule
run_migration

[[ ! -e $power_rule && ! -e $wifi_rule ]] ||
  fail "migration removes both legacy rules in one pass"
(( $(reload_count) == 2 )) ||
  fail "migration reloads udev after each removal" "$(cat "$CALLS")"
pass "migration removes both legacy rules and reloads after each one"

# Removing the file and reloading the running daemon are one repair. If reload
# fails, the durable marker must keep the migration pending even though the rule
# has already disappeared from disk; a retry finishes that half before exiting.
reset_machine
write_vulnerable_wifi_rule
reload_failure_seen="$test_dir/reload-failure-seen"
rm -f "$reload_failure_seen"

set +e
FAIL_UDEV_RELOAD_ONCE_MARKER="$reload_failure_seen" run_migration
reload_status=$?
set -e

(( reload_status != 0 )) || fail "migration fails when a running udevd cannot reload"
[[ ! -e $wifi_rule && -e $wifi_reload_marker ]] ||
  fail "migration records a deleted rule whose daemon reload is still pending"
pass "migration keeps a failed udev reload pending"

run_migration

[[ ! -e $wifi_reload_marker ]] || fail "migration clears the reload marker after a successful retry"
(( $(reload_count) == 1 )) ||
  fail "migration retries the pending udev reload" "$(cat "$CALLS")"
pass "migration retries and completes a previously failed udev reload"

# A marker is created before removal. A concurrent user who sees that phase
# must not consume it and reload while the vulnerable file is still active.
reset_machine
write_vulnerable_power_rule
touch "$power_reload_marker"
run_migration

remove_line=$(grep -n '^sudo /usr/bin/rm -f .*99-power-profile\.rules$' "$CALLS" | head -n1 | cut -d: -f1)
reload_line=$(grep -n '^sudo /usr/bin/udevadm control --reload$' "$CALLS" | head -n1 | cut -d: -f1)
[[ -n $remove_line && -n $reload_line ]] || fail "concurrent repair records removal and reload" "$(cat "$CALLS")"
(( remove_line < reload_line )) || fail "a concurrent repair reloads before removing the active rule" "$(cat "$CALLS")"
[[ ! -e $power_reload_marker ]] || fail "concurrent repair leaves a completed power reload pending"
pass "a concurrent run cannot consume a marker before rule removal"

# Each rule owns its reload state. Concurrent repairs of different files cannot
# clear one another's evidence that udev still needs to reload.
reset_machine
touch "$power_reload_marker" "$wifi_reload_marker"
run_migration

(( $(reload_count) == 2 )) || fail "migration finishes both independent pending reloads" "$(cat "$CALLS")"
[[ ! -e $power_reload_marker && ! -e $wifi_reload_marker ]] ||
  fail "migration leaves an independent reload marker behind"
pass "power and Wi-Fi removals keep independent durable reload state"

# A safe replacement installed after an interrupted removal still needs one
# reload to displace the vulnerable ruleset already held by udevd.
reset_machine
cat >"$power_rule" <<'RULE'
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="/usr/local/bin/admin-power-hook"
RULE
touch "$power_reload_marker"
run_migration

[[ -e $power_rule ]] || fail "migration removes a safe replacement rule"
(( $(reload_count) == 1 )) || fail "migration does not reload a safe replacement after interruption" "$(cat "$CALLS")"
[[ ! -e $power_reload_marker ]] || fail "migration leaves the replacement reload pending"
pass "migration reloads a safe replacement after an interrupted removal"

# A chroot or stopped daemon has no in-memory ruleset to update. An absent udev
# control socket is therefore a completed removal, not a permanent migration
# failure waiting for a daemon that is not running.
reset_machine
rm -f "$udev_control"
write_vulnerable_wifi_rule
run_migration

[[ ! -e $wifi_rule && ! -e $wifi_reload_marker ]] ||
  fail "migration completes the disk-only repair when udevd is not running"
(( $(reload_count) == 0 )) ||
  fail "migration does not contact an absent udevd" "$(cat "$CALLS")"
pass "migration permits environments with no running udev daemon"

# The second run is what every other account on the machine does, and what a
# user gets from running omarchy-migrate again.
run_migration

(( $(reload_count) == 0 )) ||
  fail "migration does not reload udev on a second run" "$(cat "$CALLS")"
[[ ! -s $CALLS ]] ||
  fail "migration touches nothing on a second run" "$(cat "$CALLS")"
pass "migration is a no-op on a second run"

reset_machine
run_migration

[[ ! -s $CALLS ]] ||
  fail "migration touches nothing when the legacy rules are absent" "$(cat "$CALLS")"
pass "migration leaves a machine without the legacy rules alone"

# An unreadable same-named file cannot safely be classified as generated or
# custom. Require an administrator rather than silently disabling their rule.
reset_machine
write_vulnerable_power_rule
chmod 000 "$power_rule"

set +e
run_migration 2>"$test_dir/unreadable-rule.out"
unreadable_status=$?
set -e

(( unreadable_status != 0 )) || fail "migration accepts a rule it could not inspect"
[[ -e $power_rule ]] || fail "migration disables a rule it could not inspect"
grep -q 'Ask an administrator to run omarchy-migrate' "$test_dir/unreadable-rule.out" ||
  fail "migration gives no administrator guidance for an unreadable rule" "$(cat "$test_dir/unreadable-rule.out")"
[[ ! -s $CALLS ]] || fail "migration escalates before classifying an unreadable rule" "$(cat "$CALLS")"
chmod 644 "$power_rule"
pass "migration fails without changing an unreadable administrator rule"

reset_machine
write_vulnerable_power_rule
chmod 600 "$rules_dir"

set +e
run_migration 2>"$test_dir/unsearchable-rules-dir.out"
unsearchable_status=$?
set -e

(( unsearchable_status != 0 )) || fail "migration accepts a rules directory it could not inspect"
grep -q 'Ask an administrator to run omarchy-migrate' "$test_dir/unsearchable-rules-dir.out" ||
  fail "migration gives no administrator guidance for an unsearchable rules directory" "$(cat "$test_dir/unsearchable-rules-dir.out")"
[[ ! -s $CALLS ]] || fail "migration escalates before inspecting the rules directory" "$(cat "$CALLS")"
chmod 755 "$rules_dir"
pass "migration fails closed when it cannot search the rules directory"

# A user who wrote their own rule under one of these names keeps it, even when
# the file talks about the legacy checkout. udev never runs a comment.
reset_machine
cat >"$power_rule" <<'RULE'
# Replaces the rule Omarchy used to install from
# /home/someuser/.local/share/omarchy/bin/omarchy-powerprofiles-set
#SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="/home/someuser/.local/share/omarchy/bin/omarchy-powerprofiles-set"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="/usr/local/bin/my-own-power-hook"
RULE
cat >"$wifi_rule" <<'RULE'
# Kept from the old local/share/omarchy setup, rewritten to my own script
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="/usr/local/bin/my-own-wifi-hook off"
RULE
before=$(cat "$power_rule" "$wifi_rule")
run_migration

[[ -e $power_rule && -e $wifi_rule ]] ||
  fail "migration keeps same-named rules that only mention the legacy path"
[[ $(cat "$power_rule" "$wifi_rule") == "$before" ]] ||
  fail "migration leaves the user's own rules byte for byte"
[[ ! -s $CALLS ]] ||
  fail "migration escalates nothing when it removes nothing" "$(cat "$CALLS")"
pass "migration keeps same-named rules that only mention the legacy path"

# A vulnerable rule that an administrator extended is no longer the exact file
# Omarchy generated. Preserve the whole file under a suffix udev ignores rather
# than deleting their addition or leaving the vulnerable command active.
reset_machine
write_vulnerable_power_rule
cat >>"$power_rule" <<'RULE'
ACTION=="add", SUBSYSTEM=="usb", RUN+="/usr/local/sbin/admin-power-hook"
RULE
write_vulnerable_wifi_rule
cp "$power_rule" "$test_dir/mixed-power-rule.before"

set +e
run_migration 2>"$test_dir/mixed-power-rule.out"
mixed_status=$?
set -e

(( mixed_status == 0 )) || fail "migration fails after safely quarantining a modified vulnerable rule" "$(cat "$test_dir/mixed-power-rule.out")"
[[ ! -e $power_rule && -e $power_rule.omarchy-disabled && ! -e $wifi_rule ]] ||
  fail "migration leaves a modified vulnerable rule active"
cmp -s "$test_dir/mixed-power-rule.before" "$power_rule.omarchy-disabled" ||
  fail "migration changes a mixed rule while quarantining it" "$(cat "$power_rule.omarchy-disabled")"
(( $(reload_count) == 2 )) || fail "migration does not continue through every vulnerable rule after quarantine" "$(cat "$CALLS")"
grep -q 'Quarantined.*\.omarchy-disabled' "$test_dir/mixed-power-rule.out" ||
  fail "migration does not explain where it preserved a mixed rule" "$(cat "$test_dir/mixed-power-rule.out")"
[[ ! -e $power_reload_marker ]] || fail "migration leaves a completed quarantine reload pending"
grep -q '^sudo /usr/bin/mv --no-clobber -- .*99-power-profile\.rules .*99-power-profile\.rules\.omarchy-disabled$' "$CALLS" ||
  fail "migration does not pin quarantine moves to root-owned mv" "$(cat "$CALLS")"
pass "migration quarantines a mixed rule and continues repairing the machine"

run_migration
[[ ! -e $power_rule && -e $power_rule.omarchy-disabled ]] ||
  fail "a quarantine retry does not preserve the disabled rule"
[[ ! -s $CALLS ]] || fail "a quarantine retry changes machine state" "$(cat "$CALLS")"
pass "migration is a no-op after completing a quarantine"

# Reformatting RUN does not make the user-controlled command safe, but it does
# make the file something Omarchy cannot delete wholesale without guessing.
reset_machine
cat >"$wifi_rule" <<'RULE'
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN += "/home/someuser/.local/share/omarchy/bin/omarchy-wifi-powersave on"
RULE
cp "$wifi_rule" "$test_dir/reformatted-wifi-rule.before"

set +e
run_migration 2>"$test_dir/reformatted-wifi-rule.out"
reformatted_status=$?
set -e

(( reformatted_status == 0 )) || fail "migration fails after quarantining a reformatted vulnerable rule" "$(cat "$test_dir/reformatted-wifi-rule.out")"
[[ ! -e $wifi_rule && -e $wifi_rule.omarchy-disabled ]] ||
  fail "migration leaves a reformatted vulnerable rule active"
cmp -s "$test_dir/reformatted-wifi-rule.before" "$wifi_rule.omarchy-disabled" ||
  fail "migration changes a reformatted rule while quarantining it" "$(cat "$wifi_rule.omarchy-disabled")"
(( $(reload_count) == 1 )) || fail "migration does not reload udev after quarantining a reformatted rule" "$(cat "$CALLS")"
pass "migration quarantines reformatted vulnerable rules"

# All assignment forms udev accepts for RUN can execute the same user-home
# helper. None may evade the conservative quarantine detector.
variant_number=0
for run_assignment in 'RUN{program}+=' 'RUN=' 'RUN:=' 'RUN+=e'; do
  ((++variant_number))
  reset_machine
  printf 'SUBSYSTEM=="power_supply", ATTR{type}=="Mains", %s"/home/someuser/.local/share/omarchy/bin/omarchy-wifi-powersave on"\n' "$run_assignment" >"$wifi_rule"
  cp "$wifi_rule" "$test_dir/run-variant-$variant_number.before"

  set +e
  run_migration 2>"$test_dir/run-variant-$variant_number.out"
  variant_status=$?
  set -e

  (( variant_status == 0 )) || fail "migration fails after quarantining udev assignment $run_assignment" "$(cat "$test_dir/run-variant-$variant_number.out")"
  [[ ! -e $wifi_rule && -e $wifi_rule.omarchy-disabled ]] ||
    fail "migration leaves udev assignment $run_assignment active"
  cmp -s "$test_dir/run-variant-$variant_number.before" "$wifi_rule.omarchy-disabled" ||
    fail "migration changes udev assignment $run_assignment while quarantining it"
  (( $(reload_count) == 1 )) || fail "migration does not reload after quarantining $run_assignment" "$(cat "$CALLS")"
done
pass "migration quarantines every valid RUN assignment form"

# Never overwrite an earlier preserved file. Choose another inactive suffix so
# the active vulnerability is still neutralized without losing either copy.
reset_machine
cat >"$wifi_rule" <<'RULE'
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN="/home/someuser/.local/share/omarchy/bin/omarchy-wifi-powersave on"
RULE
cp "$wifi_rule" "$test_dir/collision-active.before"
printf '%s\n' 'older preserved rule' >"$wifi_rule.omarchy-disabled"
cp "$wifi_rule.omarchy-disabled" "$test_dir/collision-backup.before"

set +e
run_migration 2>"$test_dir/quarantine-collision.out"
collision_status=$?
set -e

(( collision_status == 0 )) || fail "migration fails to resolve an existing quarantine" "$(cat "$test_dir/quarantine-collision.out")"
[[ ! -e $wifi_rule && -e $wifi_rule.omarchy-disabled.1 ]] || fail "migration leaves the colliding vulnerable rule active"
cmp -s "$test_dir/collision-backup.before" "$wifi_rule.omarchy-disabled" || fail "migration overwrites the existing quarantine"
cmp -s "$test_dir/collision-active.before" "$wifi_rule.omarchy-disabled.1" || fail "migration changes the new quarantine"
grep -q 'Quarantined.*\.omarchy-disabled\.1' "$test_dir/quarantine-collision.out" ||
  fail "migration does not report the unique quarantine path" "$(cat "$test_dir/quarantine-collision.out")"
(( $(reload_count) == 1 )) || fail "migration does not reload after resolving a quarantine collision" "$(cat "$CALLS")"
pass "migration preserves both files on a quarantine collision"

# A comment that does not continue still hides nothing behind it: the file holds
# no active RUN+= at all and stays.
reset_machine
cat >"$power_rule" <<'RULE'
# SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="/home/someuser/.local/share/omarchy/bin/omarchy-powerprofiles-set"
RULE
run_migration

[[ -e $power_rule ]] ||
  fail "migration keeps a rule that is only ever mentioned in a comment"
pass "migration keeps a rule that is only ever mentioned in a comment"

# The May 2026 rename left an intermediate variant under the old filename that
# already ran out of /usr/bin. It duplicates the packaged rule but is not the
# privilege escalation this migration exists to clear, so it is not ours to take.
reset_machine
cat >"$power_rule" <<'RULE'
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile-ac --property=After=power-profiles-daemon.service /usr/bin/powerprofilesctl set performance"
RULE
run_migration

[[ -e $power_rule ]] ||
  fail "migration keeps a legacy filename already repointed at /usr/bin"
pass "migration keeps a legacy filename already repointed at /usr/bin"

# Homes are not all under /home, and a different account may run this
# machine-wide repair after the installer account has gone away.
reset_machine
cat >"$wifi_rule" <<RULE
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-wifi-powersave-on /srv/retired-installer/.local/share/omarchy/bin/omarchy-wifi-powersave on"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-wifi-powersave-off /srv/retired-installer/.local/share/omarchy/bin/omarchy-wifi-powersave off"
RULE
run_migration

[[ ! -e $wifi_rule ]] ||
  fail "migration removes another user's rule rooted outside /home" "$(cat "$wifi_rule")"
pass "migration removes another user's rule rooted outside /home"

# A user who cannot elevate leaves this migration pending and stops the ordered
# queue. Once an administrator removes the machine-wide file, a retry completes.
reset_machine
write_vulnerable_wifi_rule

set +e
HOME="$home_dir" \
  PATH="$test_dir/failing-bin:$PATH" \
  bash -euo pipefail "$migration" >"$test_dir/elevation-failure.out" 2>&1
failure_status=$?
set -e

(( failure_status != 0 )) || fail "migration fails when sudo cannot remove a vulnerable rule"
[[ -e $wifi_rule ]] || fail "migration keeps the vulnerable rule when its elevated removal fails"
grep -q 'Ask an administrator to run omarchy-migrate' "$test_dir/elevation-failure.out" ||
  fail "migration explains how a non-sudo user can complete the repair" "$(cat "$test_dir/elevation-failure.out")"
pass "migration fails loudly with administrator guidance when removal cannot elevate"

# If the first removal succeeds but the second one cannot elevate, the first
# rule must already have been dropped from the running udevd.
reset_machine
write_vulnerable_power_rule
write_vulnerable_wifi_rule
cat >"$test_dir/failing-bin/sudo" <<'STUB'
#!/bin/bash

printf 'sudo %s\n' "$*" >>"$CALLS"
if [[ ${1:-} == "/usr/bin/rm" && ${*: -1} == */rules.d/99-wifi-powersave.rules ]]; then
  exit 1
fi
if [[ ${1:-} == "/usr/bin/udevadm" ]]; then
  shift
  exec "$UDEVADM_STUB" "$@"
fi
exec "$@"
STUB
chmod +x "$test_dir/failing-bin/sudo"
: >"$CALLS"

set +e
HOME="$home_dir" \
  PATH="$test_dir/failing-bin:$test_dir/bin:$PATH" \
  bash -euo pipefail "$migration" >"$test_dir/partial-failure.out" 2>&1
partial_status=$?
set -e

(( partial_status != 0 )) || fail "migration fails when the second rule cannot be removed"
[[ ! -e $power_rule && -e $wifi_rule ]] || fail "migration preserves the expected partial-removal state"
[[ -e $wifi_reload_marker ]] || fail "migration records the second rule removal as still pending"
(( $(reload_count) == 1 )) ||
  fail "migration reloads udev before a later removal failure" "$(cat "$CALLS")"
pass "a later removal failure cannot leave an already-deleted rule loaded"

# Nothing named the wrong binary is ours: the same path with a different command
# is a rule this migration cannot claim to know anything about.
reset_machine
cat >"$power_rule" <<'RULE'
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="/home/someuser/.local/share/omarchy/bin/omarchy-wifi-powersave on"
RULE
run_migration

[[ -e $power_rule ]] ||
  fail "migration matches the binary the filename promises, not any home path"
pass "migration matches the binary the filename promises, not any home path"
