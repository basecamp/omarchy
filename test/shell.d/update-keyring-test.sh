#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
log_file="$test_tmp/keyring.log"
mkdir -p "$stub_bin"

# Behavior is driven by env vars so each case can pick its failure point:
# KEYRING_TEST_PKG_MISSING     exit status of omarchy-pkg-missing (default 1: installed)
# KEYRING_TEST_LIST_FAIL_ON    which --list-keys call fails, counted per run (default: none)
# KEYRING_TEST_RECV_STATUS     exit status of --recv-keys (default 0)
# KEYRING_TEST_REINSTALL_STATUS exit status of the archlinux-keyring reinstall (default 0)
cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$KEYRING_TEST_LOG"
for arg in "$@"; do
  printf '\t%s' "$arg" >>"$KEYRING_TEST_LOG"
done
printf '\n' >>"$KEYRING_TEST_LOG"

if [[ $1 == "pacman-key" && $2 == "--list-keys" ]]; then
  calls_file="$KEYRING_TEST_DIR/list-calls"
  calls=$(( $(cat "$calls_file" 2>/dev/null || echo 0) + 1 ))
  echo "$calls" >"$calls_file"
  if [[ ${KEYRING_TEST_LIST_FAIL_ON:-} == "$calls" ]]; then
    exit 1
  fi
  exit 0
fi

if [[ $1 == "pacman-key" && $2 == "--recv-keys" ]]; then
  exit "${KEYRING_TEST_RECV_STATUS:-0}"
fi

if [[ $1 == "pacman-key" && $2 == "--lsign-key" ]]; then
  exit 0
fi

if [[ $1 == "pacman" && $* == *archlinux-keyring* ]]; then
  exit "${KEYRING_TEST_REINSTALL_STATUS:-0}"
fi

exit 0
SH
chmod +x "$stub_bin/sudo"

cat >"$stub_bin/omarchy-pkg-missing" <<'SH'
#!/bin/bash

exit "${KEYRING_TEST_PKG_MISSING:-1}"
SH
chmod +x "$stub_bin/omarchy-pkg-missing"

cat >"$stub_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash

printf 'pkg-add\t%s\n' "$1" >>"$KEYRING_TEST_LOG"
exit 0
SH
chmod +x "$stub_bin/omarchy-pkg-add"

run_keyring() {
  KEYRING_TEST_LOG="$log_file" \
    KEYRING_TEST_DIR="$test_tmp" \
    PATH="$stub_bin:$PATH" \
    "$ROOT/bin/omarchy-update-keyring" "$@"
}

# Everything healthy: the key and package are present, the reinstall works.
: >"$log_file"
rm -f "$test_tmp/list-calls"
run_keyring >"$test_tmp/ok.out"

grep -F "Keys are correct" "$test_tmp/ok.out" >/dev/null ||
  fail "update-keyring reports success when the keyring is healthy" "$(cat "$test_tmp/ok.out")"
pass "update-keyring reports success when the keyring is healthy"

grep -Eq $'^sudo\tpacman\t-Sy\t--noconfirm\tarchlinux-keyring$' "$log_file" ||
  fail "update-keyring still reinstalls archlinux-keyring" "$(cat "$log_file")"
pass "update-keyring still reinstalls archlinux-keyring"

# Key and package missing: the full populate path runs and verifies at the end.
: >"$log_file"
rm -f "$test_tmp/list-calls"
KEYRING_TEST_PKG_MISSING=0 run_keyring >"$test_tmp/populate.out"

grep -F "Keys are correct" "$test_tmp/populate.out" >/dev/null ||
  fail "update-keyring populates a missing keyring and reports success" "$(cat "$test_tmp/populate.out")"
for expected in 'recv-keys' 'lsign-key' $'pkg-add\tomarchy-keyring'; do
  grep -Eq "$expected" "$log_file" ||
    fail "update-keyring populates a missing keyring and reports success" "$(cat "$log_file")"
done
pass "update-keyring populates a missing keyring and reports success"

# recv-keys failing must stop the script, not end in "Keys are correct".
: >"$log_file"
rm -f "$test_tmp/list-calls"
if KEYRING_TEST_PKG_MISSING=0 KEYRING_TEST_RECV_STATUS=1 run_keyring >"$test_tmp/recv.out" 2>&1; then
  fail "update-keyring fails when recv-keys fails"
fi
if grep -F "Keys are correct" "$test_tmp/recv.out" >/dev/null; then
  fail "update-keyring fails when recv-keys fails" "$(cat "$test_tmp/recv.out")"
fi
if grep -q 'lsign-key' "$log_file"; then
  fail "update-keyring stops at the failed recv instead of signing anyway" "$(cat "$log_file")"
fi
pass "update-keyring fails when recv-keys fails"

# A failed archlinux-keyring reinstall must not end in success either.
: >"$log_file"
rm -f "$test_tmp/list-calls"
if KEYRING_TEST_REINSTALL_STATUS=1 run_keyring >"$test_tmp/reinstall.out" 2>&1; then
  fail "update-keyring fails when the archlinux-keyring reinstall fails"
fi
if grep -F "Keys are correct" "$test_tmp/reinstall.out" >/dev/null; then
  fail "update-keyring fails when the archlinux-keyring reinstall fails" "$(cat "$test_tmp/reinstall.out")"
fi
pass "update-keyring fails when the archlinux-keyring reinstall fails"

# The closing check is what backs the success line: the first --list-keys
# passes (key present, populate skipped), the verifying one fails.
: >"$log_file"
rm -f "$test_tmp/list-calls"
if KEYRING_TEST_LIST_FAIL_ON=2 run_keyring >"$test_tmp/verify.out" 2>&1; then
  fail "update-keyring fails when the final key check fails"
fi
if grep -F "Keys are correct" "$test_tmp/verify.out" >/dev/null; then
  fail "update-keyring fails when the final key check fails" "$(cat "$test_tmp/verify.out")"
fi
pass "update-keyring fails when the final key check fails"
