#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/pacman" <<'STUB'
#!/bin/bash

printf 'pacman\t%s\n' "$*" >>"$CALL_LOG"
[[ $1 == "-Qem" ]] || exit 1
exit "${PACMAN_FOREIGN_STATUS:-0}"
STUB

cat >"$stub_bin/omarchy-pkg-aur-accessible" <<'STUB'
#!/bin/bash

printf 'accessible\n' >>"$CALL_LOG"
exit "${AUR_ACCESSIBLE_STATUS:-0}"
STUB

cat >"$stub_bin/yay" <<'STUB'
#!/bin/bash

printf 'yay\t%s\n' "$*" >>"$CALL_LOG"

if [[ $1 == "-Qua" ]]; then
  printf '%s' "${YAY_UPDATES:-}"
  printf '%s' "${YAY_QUERY_ERROR:-}" >&2
  exit "${YAY_QUERY_STATUS:-0}"
fi

exit "${YAY_TRANSACTION_STATUS:-0}"
STUB

chmod +x "$stub_bin/pacman" "$stub_bin/omarchy-pkg-aur-accessible" "$stub_bin/yay"

run_update() {
  : >"$test_tmp/calls"
  CALL_LOG="$test_tmp/calls" \
    PACMAN_FOREIGN_STATUS="${PACMAN_FOREIGN_STATUS:-0}" \
    AUR_ACCESSIBLE_STATUS="${AUR_ACCESSIBLE_STATUS:-0}" \
    YAY_UPDATES="${YAY_UPDATES:-}" \
    YAY_QUERY_STATUS="${YAY_QUERY_STATUS:-0}" \
    YAY_QUERY_ERROR="${YAY_QUERY_ERROR:-}" \
    YAY_TRANSACTION_STATUS="${YAY_TRANSACTION_STATUS:-0}" \
    OMARCHY_UPDATE_UNATTENDED="${OMARCHY_UPDATE_UNATTENDED:-}" \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    bash "$ROOT/bin/omarchy-update-aur-pkgs" >"$test_tmp/out" 2>"$test_tmp/err"
}

cat >"$test_tmp/run-interactive" <<EOF
#!/bin/bash
exec bash "$ROOT/bin/omarchy-update-aur-pkgs"
EOF
chmod +x "$test_tmp/run-interactive"

run_interactive() {
  : >"$test_tmp/calls"
  CALL_LOG="$test_tmp/calls" \
    PACMAN_FOREIGN_STATUS="${PACMAN_FOREIGN_STATUS:-0}" \
    AUR_ACCESSIBLE_STATUS="${AUR_ACCESSIBLE_STATUS:-0}" \
    YAY_UPDATES="${YAY_UPDATES:-}" \
    YAY_QUERY_STATUS="${YAY_QUERY_STATUS:-0}" \
    YAY_QUERY_ERROR="${YAY_QUERY_ERROR:-}" \
    YAY_TRANSACTION_STATUS="${YAY_TRANSACTION_STATUS:-0}" \
    OMARCHY_UPDATE_UNATTENDED="${OMARCHY_UPDATE_UNATTENDED:-}" \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    script -qefc "$test_tmp/run-interactive" /dev/null >"$test_tmp/out" 2>"$test_tmp/err" </dev/null
}

PACMAN_FOREIGN_STATUS=1 run_update || fail "a system without foreign packages reports a failure"
[[ $(<"$test_tmp/calls") == $'pacman\t-Qem' ]] ||
  fail "a system without foreign packages probes the AUR"
pass "a system without foreign packages skips the AUR"

AUR_ACCESSIBLE_STATUS=1 run_update || fail "an unavailable AUR reports a system update failure"
! grep -q '^yay' "$test_tmp/calls" || fail "an unavailable AUR invokes yay"
grep -q 'AUR is unavailable' "$test_tmp/out" || fail "an unavailable AUR is not explained"
pass "an unavailable AUR is skipped before querying packages"

YAY_QUERY_STATUS=1 run_update || fail "yay's empty status is treated as an AUR query failure"
[[ $(grep -c '^yay' "$test_tmp/calls") == 1 ]] || fail "an empty AUR query starts a transaction"
grep -q $'^yay\t-Qua --color never --ignore gcc14,gcc14-libs$' "$test_tmp/calls" ||
  fail "the AUR query reports updates that the transaction ignores"
pass "a system without pending AUR updates stops after the read-only query"

YAY_QUERY_STATUS=9 YAY_QUERY_ERROR='AUR RPC failed' run_update ||
  fail "a failed optional AUR query aborts the trusted system update"
grep -q 'Unable to determine' "$test_tmp/err" || fail "a failed AUR query is not explained"
grep -q 'AUR RPC failed' "$test_tmp/err" || fail "a failed AUR query hides yay's diagnostic"
pass "a failed AUR query warns without aborting the trusted system update"

YAY_UPDATES='example 1.0-1 -> 1.1-1' OMARCHY_UPDATE_UNATTENDED=1 run_update ||
  fail "withholding an unattended AUR update fails the trusted system update"
[[ $(grep -c '^yay' "$test_tmp/calls") == 1 ]] || fail "an unattended update starts an AUR transaction"
grep -q 'Holding AUR updates' "$test_tmp/out" || fail "an unattended AUR hold is not announced"
pass "an unattended update reports and holds pending AUR changes"

YAY_UPDATES='example 1.0-1 -> 1.1-1' run_update ||
  fail "withholding a non-terminal AUR update reports a failure"
[[ $(grep -c '^yay' "$test_tmp/calls") == 1 ]] || fail "a non-terminal update starts an AUR transaction"
grep -q 'interactive PKGBUILD review' "$test_tmp/out" || fail "a non-terminal AUR hold is not explained"
pass "a non-terminal update cannot bypass review"

# The top-level updater logs through util-linux script(1), which gives its child
# a pseudo-terminal. Ensure the caller's original non-terminal state survives
# that wrapper and remains authoritative at the AUR gate.
for command in \
  omarchy-update-lock omarchy-update-requires-free-space omarchy-update-confirm \
  omarchy-update-pkg-prune omarchy-snapshot omarchy-update-stay-awake \
  omarchy-update-dev omarchy-update-keyring omarchy-update-system-pkgs \
  omarchy-migrate omarchy-hook omarchy-update-mise omarchy-update-orphan-pkgs \
  omarchy-update-analyze-logs omarchy-update-status omarchy-update-restart; do
  printf '#!/bin/bash\nexit 0\n' >"$stub_bin/$command"
done
cat >"$stub_bin/omarchy-update-aur-pkgs" <<'STUB'
#!/bin/bash
exec bash "$ROOT/bin/omarchy-update-aur-pkgs"
STUB
real_script=$(command -v script)
cat >"$stub_bin/script" <<'STUB'
#!/bin/bash
exec "$REAL_SCRIPT" "$1" "$2" "$TEST_UPDATE_LOG"
STUB
chmod +x "$stub_bin"/omarchy-* "$stub_bin/script"

: >"$test_tmp/calls"
if ! env -u OMARCHY_UPDATE_LOGGED \
  -u OMARCHY_UPDATE_CALLER_TTY0 -u OMARCHY_UPDATE_CALLER_TTY1 -u OMARCHY_UPDATE_CALLER_TTY2 \
  ROOT="$ROOT" CALL_LOG="$test_tmp/calls" YAY_UPDATES='example 1.0-1 -> 1.1-1' \
  REAL_SCRIPT="$real_script" TEST_UPDATE_LOG="$test_tmp/update.log" \
  PATH="$stub_bin:$ROOT/bin:$PATH" bash "$ROOT/bin/omarchy-update" </dev/null >"$test_tmp/out" 2>"$test_tmp/err"; then
  fail "a top-level non-terminal update fails while holding AUR changes"
fi
[[ $(grep -c '^yay' "$test_tmp/calls") == 1 ]] || fail "the top-level pseudo-terminal starts an AUR transaction"
grep -q 'Holding AUR updates' "$test_tmp/out" || fail "the top-level non-terminal AUR hold is not announced"
[[ -s $test_tmp/update.log ]] || fail "the isolated update logger does not write its test transcript"
pass "the update logger cannot turn a non-terminal caller into an AUR reviewer"
rm -f "$stub_bin/script"

YAY_UPDATES='example 1.0-1 -> 1.1-1' run_interactive || fail "a reviewed AUR update reports a failure"
transaction=$(grep $'^yay\t-Sua' "$test_tmp/calls")
[[ $transaction == *"--cleanafter"* ]] || fail "the reviewed update no longer cleans successful builds"
[[ $transaction == *"--ignore gcc14,gcc14-libs"* ]] || fail "the reviewed update lost its compatibility ignore list"
[[ $transaction != *"--noconfirm"* ]] || fail "the reviewed update still suppresses confirmation"
pass "an interactive update enforces the emergency review gate"

YAY_UPDATES='example 1.0-1 -> 1.1-1' YAY_TRANSACTION_STATUS=1 run_interactive ||
  fail "declining an optional AUR update aborts the trusted system update"
grep -q 'AUR packages were not updated' "$test_tmp/out" || fail "a declined AUR update is not explained"
pass "declining an AUR transaction reports the hold without aborting the update"

YAY_UPDATES='example 1.0-1 -> 1.1-1' YAY_TRANSACTION_STATUS=17 run_interactive ||
  fail "a broken optional AUR build aborts the trusted system update"
grep -q 'AUR packages were not updated' "$test_tmp/out" || fail "a broken AUR build is not explained"
pass "a broken AUR transaction remains optional to the system update"
