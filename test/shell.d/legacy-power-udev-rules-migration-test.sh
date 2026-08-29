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

# Homes are not all under /home, so the running user's own home counts too, and
# the argument the later variants passed must not hide the path.
reset_machine
cat >"$wifi_rule" <<RULE
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-wifi-powersave-on $home_dir/.local/share/omarchy/bin/omarchy-wifi-powersave on"
RULE
run_migration

[[ ! -e $wifi_rule ]] ||
  fail "migration removes a rule that runs out of a home outside /home" "$(cat "$wifi_rule")"
pass "migration removes a rule that runs out of a home outside /home"

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

# udev resumes a continuation across a comment: `udevadm verify` on
# 'SUBSYSTEM=="power_supply" \' + "# c" + ', RUN+="..."' reports its style warning
# on line 1, so those three lines are one rule and the rule is live.
reset_machine
cat >"$power_rule" <<'RULE'
SUBSYSTEM=="power_supply", ATTR{type}=="Mains" \
# split for readability
, RUN+="/home/someuser/.local/share/omarchy/bin/omarchy-powerprofiles-set"
RULE
run_migration

[[ ! -e $power_rule ]] ||
  fail "migration removes a rule that continues across a comment" "$(cat "$power_rule")"
pass "migration removes a rule that continues across a comment"
