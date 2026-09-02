#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/omarchy-pkg-missing" <<'STUB'
#!/bin/bash
exit "${PKG_MISSING_STATUS:-0}"
STUB

cat >"$stub_bin/pacman" <<'STUB'
#!/bin/bash
[[ $1 == "-Q" ]] || exit 1
exit "${PACMAN_QUERY_STATUS:-0}"
STUB

cat >"$stub_bin/yay" <<'STUB'
#!/bin/bash
printf 'yay\t%s\n' "$*" >>"$CALL_LOG"
if [[ ${YAY_FRESH_CACHE:-0} == 1 && " $* " == *" --editmenu --answeredit All "* ]]; then
  printf 'pkgname=first-seen-example\nprepare() { :; }\n'
fi
exit "${YAY_STATUS:-0}"
STUB

chmod +x "$stub_bin/omarchy-pkg-missing" "$stub_bin/pacman" "$stub_bin/yay"

cat >"$test_tmp/run-add" <<EOF
#!/bin/bash
exec bash "$ROOT/bin/omarchy-pkg-aur-add" example second-example
EOF
chmod +x "$test_tmp/run-add"

run_add() {
  : >"$test_tmp/calls"
  CALL_LOG="$test_tmp/calls" \
    PKG_MISSING_STATUS="${PKG_MISSING_STATUS:-0}" \
    PACMAN_QUERY_STATUS="${PACMAN_QUERY_STATUS:-0}" \
    YAY_STATUS="${YAY_STATUS:-0}" \
    YAY_FRESH_CACHE="${YAY_FRESH_CACHE:-0}" \
    OMARCHY_UPDATE_UNATTENDED="${OMARCHY_UPDATE_UNATTENDED:-}" \
    OMARCHY_UPDATE_CALLER_TTY="${OMARCHY_UPDATE_CALLER_TTY:-}" \
    PATH="$stub_bin:$PATH" \
    bash "$ROOT/bin/omarchy-pkg-aur-add" example second-example >"$test_tmp/out" 2>"$test_tmp/err"
}

run_add_interactive() {
  : >"$test_tmp/calls"
  CALL_LOG="$test_tmp/calls" \
    PKG_MISSING_STATUS="${PKG_MISSING_STATUS:-0}" \
    PACMAN_QUERY_STATUS="${PACMAN_QUERY_STATUS:-0}" \
    YAY_STATUS="${YAY_STATUS:-0}" \
    YAY_FRESH_CACHE="${YAY_FRESH_CACHE:-0}" \
    OMARCHY_UPDATE_UNATTENDED="${OMARCHY_UPDATE_UNATTENDED:-}" \
    OMARCHY_UPDATE_CALLER_TTY="${OMARCHY_UPDATE_CALLER_TTY:-1}" \
    PATH="$stub_bin:$PATH" \
    script -qefc "$test_tmp/run-add" /dev/null >"$test_tmp/out" 2>"$test_tmp/err" </dev/null
}

if run_add; then
  fail "a non-terminal AUR install bypasses interactive review"
fi
[[ ! -s $test_tmp/calls ]] || fail "a non-terminal AUR install invokes yay"
grep -q 'interactive PKGBUILD review' "$test_tmp/err" || fail "a non-terminal AUR install is not explained"
pass "a non-terminal AUR install is rejected before yay"

if OMARCHY_UPDATE_UNATTENDED=1 run_add_interactive; then
  fail "an unattended AUR install uses its pseudo-terminal to bypass review"
fi
[[ ! -s $test_tmp/calls ]] || fail "an unattended AUR install invokes yay"
pass "unattended mode cannot bypass AUR review with a pseudo-terminal"

if OMARCHY_UPDATE_CALLER_TTY=0 run_add_interactive; then
  fail "an update logger pseudo-terminal bypasses AUR install review"
fi
[[ ! -s $test_tmp/calls ]] || fail "a synthetic update pseudo-terminal invokes yay"
pass "the original update caller must have a terminal before an AUR install"

run_add_interactive || fail "an interactive AUR install reports a failure"
transaction=$(grep $'^yay\t-S' "$test_tmp/calls")
[[ $transaction == *"--aur"* ]] || fail "the reviewed install is not restricted to the AUR"
[[ $transaction == *"--confirm"* ]] || fail "the reviewed install does not require final confirmation"
[[ $transaction == *"--diffmenu --answerdiff All"* ]] || fail "the reviewed install does not show every build-file diff"
[[ $transaction == *"--editmenu --answeredit All"* ]] || fail "the reviewed install does not show full first-seen build recipes"
[[ $transaction == *"-- example second-example"* ]] || fail "package names are not separated from yay options"
[[ $transaction != *"--noconfirm"* ]] || fail "the reviewed install still suppresses confirmation"
pass "an interactive AUR install enforces the emergency review gate"

YAY_FRESH_CACHE=1 run_add_interactive || fail "a first-seen AUR install reports a failure"
grep -q 'pkgname=first-seen-example' "$test_tmp/out" || fail "a first-seen PKGBUILD is not presented to the reviewer"
grep -q 'prepare()' "$test_tmp/out" || fail "a first-seen PKGBUILD body is not presented to the reviewer"
pass "a fresh-cache install requests the complete first-seen PKGBUILD view"

if YAY_STATUS=19 run_add_interactive; then
  fail "a failed reviewed AUR install reports success"
fi
pass "a failed reviewed AUR install propagates its status"

PKG_MISSING_STATUS=1 run_add || fail "an already installed AUR package requires a terminal"
[[ ! -s $test_tmp/calls ]] || fail "an already installed AUR package invokes yay"
pass "an already installed package remains a no-op"

if rg -n -- '--noconfirm' \
  "$ROOT/bin/omarchy-pkg-aur-add" \
  "$ROOT/bin/omarchy-pkg-aur-install" \
  "$ROOT/bin/omarchy-update-aur-pkgs" >"$test_tmp/noconfirm"; then
  fail "an Omarchy AUR transaction still contains --noconfirm" "$(<"$test_tmp/noconfirm")"
fi
pass "supported AUR install and update paths contain no --noconfirm bypass"

if rg -n 'omarchy-sudo-keepalive|xargs yay' "$ROOT/bin/omarchy-pkg-aur-install" >"$test_tmp/picker-bypass"; then
  fail "the AUR picker still overlaps a sudo keepalive or bypasses the reviewed installer" "$(<"$test_tmp/picker-bypass")"
fi
grep -q 'omarchy-pkg-aur-add "${pkg_names\[@\]}"' "$ROOT/bin/omarchy-pkg-aur-install" ||
  fail "the AUR picker does not route selections through the reviewed installer"
pass "the AUR picker routes selections through the reviewed installer without sudo keepalive"

cat >"$stub_bin/omarchy-pkg-present" <<'STUB'
#!/bin/bash
exit 0
STUB
cat >"$stub_bin/omarchy-pkg-aur-add" <<'STUB'
#!/bin/bash
exit 2
STUB
cat >"$stub_bin/omarchy-pkg-drop" <<'STUB'
#!/bin/bash
printf 'drop\t%s\n' "$*" >>"$CALL_LOG"
STUB
cat >"$stub_bin/xdg-settings" <<'STUB'
#!/bin/bash
printf 'brave-origin-beta.desktop\n'
STUB
chmod +x "$stub_bin/omarchy-pkg-present" "$stub_bin/omarchy-pkg-aur-add" \
  "$stub_bin/omarchy-pkg-drop" "$stub_bin/xdg-settings"

: >"$test_tmp/calls"
if CALL_LOG="$test_tmp/calls" HOME="$test_tmp/home" OMARCHY_PATH="$ROOT" PATH="$stub_bin:$PATH" \
  bash -euo pipefail "$ROOT/migrations/1784510887.sh" >"$test_tmp/migration.out" 2>"$test_tmp/migration.err"; then
  fail "a withheld Brave replacement marks the incomplete migration complete"
fi
[[ ! -s $test_tmp/calls ]] || fail "a withheld Brave replacement removes the installed beta"
grep -q 'Keeping Brave Origin Beta' "$test_tmp/migration.out" || fail "a withheld Brave replacement is not explained"
pass "the Brave migration stays pending and preserves the installed browser when AUR review is withheld"

cat >"$stub_bin/omarchy-install-emacs" <<'STUB'
#!/bin/bash
printf 'configure\n' >>"$CALL_LOG"
STUB
cat >"$stub_bin/setsid" <<'STUB'
#!/bin/bash
printf 'launch\n' >>"$CALL_LOG"
STUB
chmod +x "$stub_bin/omarchy-install-emacs" "$stub_bin/setsid"

: >"$test_tmp/calls"
if CALL_LOG="$test_tmp/calls" PATH="$stub_bin:$PATH" bash "$ROOT/bin/omarchy-install-editor-emacs" \
  >"$test_tmp/emacs.out" 2>"$test_tmp/emacs.err"; then
  fail "the Emacs installer reports success after AUR review is withheld"
fi
[[ ! -s $test_tmp/calls ]] || fail "the Emacs installer configures or launches after AUR review is withheld"
pass "the Emacs installer stops when its AUR package is withheld"
