#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

policy="$ROOT/bin/omarchy-theme-browser-policy"
sudoers_file="$ROOT/etc/sudoers.d/omarchy-theme-browser-policy"
rule='%wheel ALL=(root) NOPASSWD: /usr/bin/omarchy-theme-browser-policy *'

rules=$(grep -vE '^[[:space:]]*(#|$)' "$sudoers_file")
[[ $rules == "$rule" ]] ||
  fail "browser theme policy sudoers file contains exactly the constrained helper rule" "got: $rules"

if command -v visudo >/dev/null; then
  visudo -cf "$sudoers_file" >/dev/null ||
    fail "browser theme policy sudoers rule parses"
fi

grep -Fx 'PACKAGED_PATH=/usr/bin/omarchy-theme-browser-policy' "$policy" >/dev/null ||
  fail "browser theme policy elevates the packaged path"

grep -E 'sudo -n -l -l' "$policy" >/dev/null ||
  fail "browser theme policy reads the passwordless grant from sudo's long listing"

gated=$(grep -A1 -E '^if \(\( EUID == 0 \)\); then$' "$policy" || true)
[[ $gated == *"export PATH=/usr/local/sbin:/usr/local/bin:/usr/bin"* ]] ||
  fail "browser theme policy pins PATH only after it holds root"

expected_dirs=$'/etc/chromium/policies/managed\n/etc/opt/chrome/policies/managed\n/etc/opt/edge/policies/managed\n/etc/brave/policies/managed'
policy_dirs=$(awk '
  /^POLICY_DIRS=\($/ { inside = 1; next }
  inside && /^\)$/ { exit }
  inside { gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print }
' "$policy")
[[ $policy_dirs == "$expected_dirs" ]] ||
  fail "browser theme policy writes only the supported Chromium policy paths" "got: $policy_dirs"

pass "browser theme policy fixes its authorization, command, and destination paths"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
elevation_log="$test_tmp/elevation"
mkdir -p "$stub_bin"

cat >"$stub_bin/pkexec" <<'SH'
#!/bin/bash
printf 'pkexec %s\n' "$*" >"$ELEVATION_LOG"
SH

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
if [[ $1 == -n && $2 == -l && $3 == -l ]]; then
  if [[ ${STUB_GRANTED-1} == 1 ]]; then
    echo "    Options: !authenticate"
  fi
  exit 0
fi

printf 'sudo %s\n' "$*" >"$ELEVATION_LOG"
SH

chmod +x "$stub_bin/pkexec" "$stub_bin/sudo"

run_policy() {
  : >"$elevation_log"
  ELEVATION_LOG="$elevation_log" \
  PATH="$stub_bin:$PATH" \
    bash "$policy" "$@" </dev/null
}

assert_rejected() {
  local description=$1
  shift

  if run_policy "$@" >"$test_tmp/rejected.out" 2>&1; then
    fail "$description"
  fi
  [[ ! -s $elevation_log ]] ||
    fail "$description before attempting elevation" "got: $(<"$elevation_log")"
}

assert_rejected "browser theme policy rejects a missing color"
assert_rejected "browser theme policy rejects a color without a hash" "112233"
assert_rejected "browser theme policy rejects short colors" "#12345"
assert_rejected "browser theme policy rejects non-hex colors" "#12gg33"
assert_rejected "browser theme policy rejects option-like input" "--help"
assert_rejected "browser theme policy rejects extra arguments" "#112233" "#445566"
assert_rejected "browser theme policy rejects input containing a newline" $'#112233\n/etc/passwd'

pass "browser theme policy accepts only one six-digit hex color"

# A direct root run would reach the real policy directories before these PATH
# stubs could stop it, because root intentionally pins PATH. The static checks
# and all validation coverage above remain safe under a root-run test suite.
if (( EUID == 0 )); then
  pass "running as root; skipping unprivileged elevation routing"
  exit 0
fi

run_policy "#A1b2C3" >/dev/null
elevation=$(<"$elevation_log")
[[ $elevation == "sudo /usr/bin/omarchy-theme-browser-policy #A1b2C3" ]] ||
  fail "browser theme policy uses its passwordless sudo grant" "got: $elevation"

OMARCHY_PATH="$test_tmp/checkout" run_policy "#A1b2C3" >/dev/null
elevation=$(<"$elevation_log")
[[ $elevation == "sudo /usr/bin/omarchy-theme-browser-policy #A1b2C3" ]] ||
  fail "a dev-linked browser policy command still elevates the packaged path" "got: $elevation"

STUB_GRANTED="" run_policy "#A1b2C3" >/dev/null
elevation=$(<"$elevation_log")
[[ $elevation == "pkexec /usr/bin/omarchy-theme-browser-policy #A1b2C3" ]] ||
  fail "browser theme policy falls back to polkit without the sudoers grant" "got: $elevation"

pass "browser theme policy routes elevation without exposing checkout code"
