#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

passwordless="$ROOT/bin/omarchy-sudo-passwordless"

grep -Fq 'user=$(id -un)' "$passwordless" ||
  fail "passwordless sudo takes the username from id -un"

grep -Fq 'echo "${user} ALL=(ALL) NOPASSWD: ALL"' "$passwordless" ||
  fail "passwordless sudo writes the id -un subject into sudoers"

grep -Fq 'NOPASSWD_FILE="/etc/sudoers.d/99-omarchy-nopasswd-${user}"' "$passwordless" ||
  fail "passwordless sudo names the drop-in from id -un"

! grep -Fq '${USER}' "$passwordless" ||
  fail "passwordless sudo does not interpolate USER into sudoers"

grep -Fq 'id -nG 2>/dev/null' "$ROOT/bin/omarchy-sudo-docker" ||
  fail "sudoless Docker --configured reads groups of the current euid"

for cmd in \
  "$ROOT/bin/omarchy-setup-security-sudoless-docker" \
  "$ROOT/bin/omarchy-remove-security-sudoless-docker" \
  "$ROOT/bin/omarchy-dev-install-ydoo" \
  "$ROOT/bin/omarchy-install-service-tailscale" \
  "$ROOT/bin/omarchy-install-gaming-xbox-controllers" \
  "$ROOT/bin/omarchy-install-service-nordvpn"
do
  grep -Fq 'user=$(id -un)' "$cmd" ||
    fail "$(basename "$cmd") takes the username from id -un"
  ! grep -Fq '"$USER"' "$cmd" ||
    fail "$(basename "$cmd") does not pass USER to a privileged command"
done

grep -Fq 'fprintd-enroll "$(id -un)"' "$ROOT/bin/omarchy-setup-security-fingerprint" ||
  fail "fingerprint enroll uses id -un"

pass "privileged commands take the username from the euid, not USER"
