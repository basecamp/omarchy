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
    YAY_TRANSACTION_STATUS="${YAY_TRANSACTION_STATUS:-0}" \
    OMARCHY_UPDATE_UNATTENDED="${OMARCHY_UPDATE_UNATTENDED:-}" \
    PATH="$stub_bin:$PATH" \
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
    YAY_TRANSACTION_STATUS="${YAY_TRANSACTION_STATUS:-0}" \
    OMARCHY_UPDATE_UNATTENDED="${OMARCHY_UPDATE_UNATTENDED:-}" \
    PATH="$stub_bin:$PATH" \
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

run_update || fail "a system without pending AUR updates reports a failure"
[[ $(grep -c '^yay' "$test_tmp/calls") == 1 ]] || fail "an empty AUR query starts a transaction"
pass "a system without pending AUR updates stops after the read-only query"

YAY_QUERY_STATUS=9 run_update && fail "a failed AUR query passes for no updates"
grep -q 'Unable to determine' "$test_tmp/err" || fail "a failed AUR query is not explained"
pass "a failed AUR query fails closed"

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
chmod +x "$stub_bin"/omarchy-*

: >"$test_tmp/calls"
if ! env -u OMARCHY_UPDATE_LOGGED -u OMARCHY_UPDATE_CALLER_TTY \
  ROOT="$ROOT" CALL_LOG="$test_tmp/calls" YAY_UPDATES='example 1.0-1 -> 1.1-1' \
  PATH="$stub_bin:$PATH" bash "$ROOT/bin/omarchy-update" </dev/null >"$test_tmp/out" 2>"$test_tmp/err"; then
  fail "a top-level non-terminal update fails while holding AUR changes"
fi
[[ $(grep -c '^yay' "$test_tmp/calls") == 1 ]] || fail "the top-level pseudo-terminal starts an AUR transaction"
grep -q 'Holding AUR updates' "$test_tmp/out" || fail "the top-level non-terminal AUR hold is not announced"
pass "the update logger cannot turn a non-terminal caller into an AUR reviewer"

YAY_UPDATES='example 1.0-1 -> 1.1-1' run_interactive || fail "a reviewed AUR update reports a failure"
transaction=$(grep $'^yay\t-Sua' "$test_tmp/calls")
[[ $transaction == *"--aur"* ]] || fail "the reviewed update is not restricted to the AUR"
[[ $transaction == *"--confirm"* ]] || fail "the reviewed update does not require final confirmation"
[[ $transaction == *"--diffmenu --answerdiff All"* ]] || fail "the reviewed update does not show every build-file diff"
[[ $transaction == *"--editmenu --answeredit All"* ]] || fail "the reviewed update does not show full first-seen build recipes"
[[ $transaction == *"--cleanafter"* ]] || fail "the reviewed update no longer cleans successful builds"
[[ $transaction == *"--ignore gcc14,gcc14-libs"* ]] || fail "the reviewed update lost its compatibility ignore list"
[[ $transaction != *"--noconfirm"* ]] || fail "the reviewed update still suppresses confirmation"
pass "an interactive update enforces the emergency review gate"

if YAY_UPDATES='example 1.0-1 -> 1.1-1' YAY_TRANSACTION_STATUS=17 run_interactive; then
  fail "a failed AUR transaction is masked by later output"
fi
pass "a failed AUR transaction propagates its status"
