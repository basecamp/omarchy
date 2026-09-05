#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

remove="$ROOT/bin/omarchy-remove-security-fingerprint"

test_tmp=$(mktemp -d)
stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
remove_copy="$test_tmp/remove.sh"
mkdir -p "$stub_bin"
trap 'rm -rf "$test_tmp"' EXIT

# remove_pam_config and remove_lock_fingerprint_pam edit/remove absolute
# system paths (/etc/pam.d/*) this suite has no business touching, and their
# own logic is unchanged by this fix. Blank out their bodies in a scratch
# copy so only the package-removal branch below -- the actual fix -- runs.
occurrences=$(grep -c '^remove_pam_config() {$\|^remove_lock_fingerprint_pam() {$' "$remove") || occurrences=0
(( occurrences == 2 )) ||
  fail "removal defines exactly the two PAM helper functions expected" "found $occurrences"

sed -e '/^remove_pam_config() {$/,/^}$/c\
remove_pam_config() {\
  :\
}' \
    -e '/^remove_lock_fingerprint_pam() {$/,/^}$/c\
remove_lock_fingerprint_pam() {\
  :\
}' \
    "$remove" >"$remove_copy"
chmod +x "$remove_copy"
pass "removal's PAM-editing helpers are neutralized in the copy under test"

cat >"$stub_bin/omarchy-pkg-drop" <<SH
#!/bin/bash
printf 'drop\t%s\n' "\$*" >>"$calls"
SH
chmod +x "$stub_bin/omarchy-pkg-drop"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
exec "$@"
SH
chmod +x "$stub_bin/sudo"

run_removal() {
  : >"$calls"
  PATH="$stub_bin:$PATH" OMARCHY_PKG_PRESENT_RESULT="$1" bash "$remove_copy" 2>&1
}

cat >"$stub_bin/omarchy-pkg-present" <<'SH'
#!/bin/bash
[[ "$OMARCHY_PKG_PRESENT_RESULT" == "present" ]]
SH
chmod +x "$stub_bin/omarchy-pkg-present"

output=$(run_removal present)
[[ "$(cat "$calls")" == "drop	fprintd libfprint libfprint-git" ]] ||
  fail "removal drops the fprintd packages when Omarchy's own fprintd is installed" "$(cat "$calls")"
pass "removal drops the fprintd packages when Omarchy's own fprintd is installed"

output=$(run_removal absent)
[[ ! -s "$calls" ]] ||
  fail "removal leaves packages alone when fprintd isn't installed" "$(cat "$calls")"
[[ "$output" == *"Leaving the installed fingerprint packages alone"* ]] ||
  fail "removal explains why it left the packages alone" "$output"
pass "removal leaves a BYO fprintd-compatible stack's packages alone"

### remove.security.fingerprint menu gate ###

menu="$ROOT/default/omarchy/omarchy-menu.jsonc"
gate=$(grep -o '"remove\.security\.fingerprint":[^}]*}' "$menu")
[[ "$gate" == *'omarchy-pkg-present fprintd'* ]] ||
  fail "removal menu entry still checks for Omarchy's own fprintd package"
[[ "$gate" == *'pam_fprintd.so'* ]] ||
  fail "removal menu entry also shows up for a BYO stack with fingerprint PAM configured" "$gate"
pass "removal menu entry shows for either Omarchy's own fprintd or a configured BYO stack"
