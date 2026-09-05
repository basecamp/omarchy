#!/bin/bash

set -euo pipefail

# Omarchy ships hardening-adjacent sysctls in etc/sysctl.d/. kptr_restrict=1
# must stay present so unprivileged readers cannot harvest kernel addresses
# from /proc while root workflows keep working.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

conf="$ROOT/etc/sysctl.d/99-omarchy-sysctl.conf"
[[ -f $conf ]] || fail "99-omarchy-sysctl.conf is packaged under etc/sysctl.d"

grep -Eq '^[[:space:]]*kernel\.kptr_restrict[[:space:]]*=[[:space:]]*1[[:space:]]*$' "$conf" ||
  fail "99-omarchy-sysctl.conf sets kernel.kptr_restrict=1" "$(grep kptr "$conf" || true)"

# Do not ship a looser value that would undo distro/admin hardening.
! grep -Eq '^[[:space:]]*kernel\.kptr_restrict[[:space:]]*=[[:space:]]*0[[:space:]]*$' "$conf" ||
  fail "99-omarchy-sysctl.conf must not set kptr_restrict=0"

pass "sysctl drop-in hides kernel pointers from unprivileged users"

migration="$ROOT/migrations/1788139000.sh"
[[ -f $migration ]] || fail "a migration applies the kptr_restrict drop-in on existing installs"
grep -q '99-omarchy-sysctl.conf' "$migration" ||
  fail "migration loads the omarchy sysctl drop-in specifically"
grep -q 'sysctl -p' "$migration" ||
  fail "migration applies the drop-in at runtime rather than only on next boot"

pass "migration reapplies the sysctl drop-in without waiting for reboot"
