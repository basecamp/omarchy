#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

script="$ROOT/bin/omarchy-sudo-passwordless"
tmpfiles_file="$ROOT/etc/tmpfiles.d/omarchy-nopasswd-sudo.conf"

[[ -f $tmpfiles_file ]] ||
  fail "a tmpfiles rule clears passwordless sudo grants at boot"

# Exactly one rule. A second line here removes something at every boot on every
# machine, so this file has no room for a passenger.
rules=$(grep -vE '^[[:space:]]*(#|$)' "$tmpfiles_file")
(( $(grep -c . <<<"$rules") == 1 )) ||
  fail "the boot cleanup carries exactly one rule" "got: $rules"

read -r rule_type rule_path _ <<<"$rules"

# r is the removal type, and it runs whenever systemd-tmpfiles is called with
# --remove, which is not only at boot. The ! holds it to runs that also pass
# --boot, so a manual systemd-tmpfiles --remove cannot cut a live grant short
# mid-window.
[[ $rule_type == 'r!' ]] ||
  fail "the boot cleanup removes at boot only" "got: $rule_type"

pass "the boot cleanup is a single boot-only removal"

# The rule and the script have to keep naming the same file. If either side is
# renamed on its own, the grant quietly stops being cleared and nothing fails.
script_path=$(grep -m1 '^NOPASSWD_FILE=' "$script" | cut -d'"' -f2)
[[ -n $script_path ]] ||
  fail "the script names the grant file it writes"

granted=${script_path/'${USER}'/alice}
# shellcheck disable=SC2053
[[ $granted == $rule_path ]] ||
  fail "the boot cleanup matches the grant the script writes" "grant: $granted, rule: $rule_path"

pass "the boot cleanup matches the grant the script writes"

# Everything else under /etc/sudoers.d is a rule Omarchy means to keep. A glob
# that reached any of them would drop it at every boot.
for shipped in "$ROOT"/etc/sudoers.d/*; do
  [[ -f $shipped ]] || continue
  installed="/etc/sudoers.d/$(basename "$shipped")"
  # shellcheck disable=SC2053
  if [[ $installed == $rule_path ]]; then
    fail "the boot cleanup leaves the shipped sudoers rules alone" "would remove: $installed"
  fi
done

pass "the boot cleanup leaves the shipped sudoers rules alone"

# The timer the script arms is transient, which is the whole reason the boot
# rule exists. If this ever becomes a persistent unit the rule is still correct,
# but the reason recorded in both files would no longer be.
grep -q 'systemd-run --on-active' "$script" ||
  fail "the script still expires the grant with a transient timer"

pass "the script still expires the grant with a transient timer"
