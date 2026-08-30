#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

script="$ROOT/bin/omarchy-sudo-passwordless"

grep -q 'id -un' "$script" || fail "passwordless sudo must use id -un, not \$USER"
pass "passwordless sudo uses id -un"

grep -q 'MAX_MINUTES=120' "$script" || fail "passwordless sudo must cap duration"
pass "passwordless sudo caps duration"

grep -q 'omarchy-nopasswd-boot-cleanup.service' "$script" ||
  fail "passwordless sudo must install a boot cleanup unit"
pass "passwordless sudo installs a boot cleanup unit"

grep -q 'schedule_expire' "$script" || fail "passwordless sudo must fail closed if the timer cannot arm"
pass "passwordless sudo fails closed if the timer cannot arm"

# The unit body must delete every Omarchy nopasswd drop-in on boot.
grep -F "rm -f /etc/sudoers.d/99-omarchy-nopasswd-*" "$script" ||
  fail "boot cleanup must remove 99-omarchy-nopasswd-* drop-ins"
pass "boot cleanup removes 99-omarchy-nopasswd-* drop-ins"
