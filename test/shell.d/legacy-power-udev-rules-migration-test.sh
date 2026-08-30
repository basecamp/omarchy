#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

migration="$ROOT/migrations/1787946619.sh"
[[ -f $migration ]] || fail "the legacy power udev rule migration exists at $migration"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/bin"

# sudo runs the real command, so the removals act on the redirected rules
# directory below and the elevated calls land in the log beside it.
cat >"$test_dir/bin/sudo" <<'STUB'
#!/bin/bash

printf 'sudo %s\n' "$*" >>"$CALLS"
exec "$@"
STUB

cat >"$test_dir/bin/udevadm" <<'STUB'
#!/bin/bash

printf 'udevadm %s\n' "$*" >>"$CALLS"
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

rules_dir="$test_dir/rules.d"
home_dir="$test_dir/home"
power_rule="$rules_dir/99-power-profile.rules"
wifi_rule="$rules_dir/99-wifi-powersave.rules"

reset_machine() {
  rm -rf "$rules_dir" "$home_dir"
  mkdir -p "$rules_dir" "$home_dir"
}

run_migration() {
  : >"$CALLS"

  HOME="$home_dir" \
    OMARCHY_UDEV_RULES_DIR="$rules_dir" \
    PATH="$test_dir/bin:$PATH" \
    bash -euo pipefail "$migration" >/dev/null
}

reload_count() {
  grep -cx 'udevadm control --reload' "$CALLS" || true
}

# What Omarchy 3's unquoted heredoc actually left on disk: the installing user's
# home expanded into a rule root runs on every power_supply event.
write_vulnerable_power_rule() {
  cat >"$power_rule" <<'RULE'
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile --property=After=power-profiles-daemon.service /home/someuser/.local/share/omarchy/bin/omarchy-powerprofiles-set"
SUBSYSTEM=="power_supply", ATTR{type}=="USB", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile --property=After=power-profiles-daemon.service /home/someuser/.local/share/omarchy/bin/omarchy-powerprofiles-set"
RULE
}

write_vulnerable_wifi_rule() {
  cat >"$wifi_rule" <<'RULE'
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="/home/someuser/.local/share/omarchy/bin/omarchy-wifi-powersave on"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="/home/someuser/.local/share/omarchy/bin/omarchy-wifi-powersave off"
RULE
}

reset_machine
write_vulnerable_power_rule
run_migration

[[ ! -e $power_rule ]] ||
  fail "migration removes a power profile rule that runs out of a user home" "$(cat "$power_rule")"
pass "migration removes a power profile rule that runs out of a user home"

grep -q '^sudo rm -f .*99-power-profile\.rules$' "$CALLS" ||
  fail "migration removes the rule with elevated privileges" "$(cat "$CALLS")"
pass "migration removes the rule with elevated privileges"

reset_machine
write_vulnerable_wifi_rule
run_migration

[[ ! -e $wifi_rule ]] ||
  fail "migration removes a Wi-Fi power save rule that runs out of a user home" "$(cat "$wifi_rule")"
pass "migration removes a Wi-Fi power save rule that runs out of a user home"

# udevd keeps running the rule it already parsed, so the file being gone from
# disk is only half the fix until it reloads.
(( $(reload_count) == 1 )) ||
  fail "migration reloads udev after removing a rule" "$(cat "$CALLS")"
pass "migration reloads udev after removing a rule"

# Both files gone is still one machine-wide reload, not one per file.
reset_machine
write_vulnerable_power_rule
write_vulnerable_wifi_rule
run_migration

[[ ! -e $power_rule && ! -e $wifi_rule ]] ||
  fail "migration removes both legacy rules in one pass"
(( $(reload_count) == 1 )) ||
  fail "migration reloads udev once for both removals" "$(cat "$CALLS")"
pass "migration removes both legacy rules and reloads udev once"

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

# udev discards a '#' line before it ever looks for a trailing backslash, so the
# rule below the comment is live and root still runs it. `udevadm verify` on this
# exact shape, with a bogus key on the second line, reports the error on line 2.
# The file has to go.
reset_machine
cat >"$power_rule" <<'RULE'
# Disabled while I test the packaged rule: \
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="/home/someuser/.local/share/omarchy/bin/omarchy-powerprofiles-set"
RULE
run_migration

[[ ! -e $power_rule ]] ||
  fail "migration removes a rule left live under a commented continuation" "$(cat "$power_rule")"
pass "migration removes a rule left live under a commented continuation"

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
RULE
run_migration

[[ ! -e $wifi_rule ]] ||
  fail "migration removes another user's rule rooted outside /home" "$(cat "$wifi_rule")"
pass "migration removes another user's rule rooted outside /home"

# A user who cannot elevate must leave this repair pending without preventing
# later migrations from running. Once another account removes the machine-wide
# file, the next retry can complete without sudo.
reset_machine
write_vulnerable_wifi_rule
defer_file="$test_dir/defer-signal"
defer_token="legacy-udev-repair"
: >"$defer_file"

set +e
HOME="$home_dir" \
  OMARCHY_UDEV_RULES_DIR="$rules_dir" \
  OMARCHY_MIGRATION_DEFER_FILE="$defer_file" \
  OMARCHY_MIGRATION_DEFER_TOKEN="$defer_token" \
  PATH="$test_dir/failing-bin:$PATH" \
  bash -euo pipefail "$migration" >"$test_dir/defer.out" 2>&1
defer_status=$?
set -e

(( defer_status == 75 )) || fail "migration defers when sudo cannot remove a vulnerable rule" "status=$defer_status"
[[ -e $wifi_rule ]] || fail "migration keeps the vulnerable rule when its elevated removal fails"
[[ $(<"$defer_file") == "$defer_token" ]] || fail "migration authenticates its deferral to the runner"
pass "migration defers instead of blocking the queue when removal cannot elevate"

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

# udev resumes a continuation across a comment: `udevadm verify` reports its
# complaint on line 1 for a rule split this way, so the three lines are one live
# rule. The split falls inside the RUN+= value on purpose -- with the whole
# RUN+= below the comment the assertion passes even against an implementation
# that throws the pending half away, which is the shape this guards against.
reset_machine
cat >"$power_rule" <<'RULE'
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="/usr/bin/systemd-run --no-block --unit=omarchy-power-profile \
# split for readability
/home/someuser/.local/share/omarchy/bin/omarchy-powerprofiles-set"
RULE
run_migration

[[ ! -e $power_rule ]] ||
  fail "migration removes a rule that continues across a comment" "$(cat "$power_rule")"
pass "migration removes a rule that continues across a comment"
