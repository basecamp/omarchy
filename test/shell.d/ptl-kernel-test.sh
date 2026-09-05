#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

script="$ROOT/install/hardware/intel/ptl-kernel.sh"

if grep -E 'pacman[[:space:]]+-Rdd.*linux-headers.*[[:space:]]linux([[:space:]]|$)|pacman[[:space:]]+-Rdd.*[[:space:]]linux[[:space:]].*linux-headers' "$script" >/dev/null; then
  fail "PTL kernel swap must not abort the whole removal when linux-headers is missing"
fi
pass "PTL kernel swap does not remove linux and linux-headers in one transaction"

grep -q 'for pkg in linux linux-headers' "$script" ||
  fail "PTL kernel swap removes each stock kernel package on its own"
grep -Fq 'pacman -Rdd --noconfirm "$pkg" ||' "$script" ||
  fail "PTL kernel swap keeps a failed package removal from aborting the boot-order drop-in"
pass "PTL kernel swap removes each stock kernel package on its own"
