#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# The fingerprint and FIDO2 setup commands each create /etc/pam.d/polkit-1 from
# scratch when the file does not already exist -- which is the normal case on
# Arch, where the polkit package ships its PAM stack in /usr/lib/pam.d/polkit-1
# and /etc/pam.d/polkit-1 is absent. A hand-rolled stack that lists pam_unix
# directly instead of `include system-auth` silently drops pam_faillock, so
# polkit prompts would have no brute-force lockout and their failures would not
# count toward the shared tally. Assert the created stack defers to system-auth.

for setup in omarchy-setup-security-fingerprint omarchy-setup-security-fido2; do
  script="$ROOT/bin/$setup"

  # Pull the here-doc body the setup writes to /etc/pam.d/polkit-1.
  body=$(sed -n "/tee \/etc\/pam.d\/polkit-1/,/^EOF\$/p" "$script")

  [[ -n $body ]] || fail "$setup writes a polkit-1 stack"

  for phase in auth account password session; do
    grep -qE "^${phase}[[:space:]]+include[[:space:]]+system-auth" <<<"$body" ||
      fail "$setup polkit-1 $phase defers to system-auth (keeps faillock)" "$body"
  done

  ! grep -qE "^(account|password|session)[[:space:]]+required[[:space:]]+pam_unix" <<<"$body" ||
    fail "$setup polkit-1 does not hand-roll a bare pam_unix stack" "$body"

  pass "$setup creates a polkit-1 stack that includes system-auth"
done
