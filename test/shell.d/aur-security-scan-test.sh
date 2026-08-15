#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
stub_bin="$test_tmp/bin"
test_home="$test_tmp/home"
yay_log="$test_tmp/yay-log"
review_log="$test_tmp/review-log"
mkdir -p "$stub_bin" "$test_home"

cat >"$stub_bin/omarchy-default-agent" <<'STUB'
#!/bin/bash
printf '%s\n' "${TEST_AGENT:-codex}"
STUB
cat >"$stub_bin/omarchy-toggle-enabled" <<'STUB'
#!/bin/bash
[[ $1 == "agent-security-scan" && ${TEST_SCANS:-0} == "1" ]]
STUB
cat >"$stub_bin/omarchy-pkg-missing" <<'STUB'
#!/bin/bash
exit 0
STUB
cat >"$stub_bin/omarchy-pkg-aur-accessible" <<'STUB'
#!/bin/bash
exit 0
STUB
cat >"$stub_bin/pacman" <<'STUB'
#!/bin/bash
exit 0
STUB
cat >"$stub_bin/yay" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_YAY_LOG"
if [[ $* == *"-Qua"* ]]; then
  printf 'bad\ngood\n'
  exit 0
fi
[[ ${!#} != "bad" ]]
STUB
cat >"$stub_bin/omarchy-agent-security-review" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_REVIEW_LOG"
[[ $* != *"--id bad "* ]]
STUB
chmod +x "$stub_bin"/*

export HOME="$test_home"
export OMARCHY_PATH="$ROOT"
export PATH="$stub_bin:$ROOT/bin:$PATH"
export TEST_YAY_LOG="$yay_log"
export TEST_REVIEW_LOG="$review_log"

: >"$yay_log"
TEST_SCANS=0 omarchy-pkg-aur-add alpha beta
[[ $(wc -l <"$yay_log") == 1 ]] || fail "disabled AUR scanning changes the existing batch install"
grep -qF -- "-S --noconfirm --needed alpha beta" "$yay_log" ||
  fail "disabled AUR scanning preserves yay's existing arguments" "$(<"$yay_log")"
pass "disabled AUR scanning preserves the original install path"

: >"$yay_log"
set +e
TEST_SCANS=1 omarchy-pkg-aur-add bad good >"$test_tmp/add-output" 2>&1
status=$?
set -e
(( status != 0 )) || fail "scanned AUR batch hides a held package"
[[ $(wc -l <"$yay_log") == 2 ]] || fail "scanned AUR batch stops before later packages" "$(<"$yay_log")"
grep -qF -- "--editmenu --answeredit All --editor omarchy-pkg-aur-verify" "$yay_log" ||
  fail "AUR install does not put the verifier in yay's pre-build editor gate" "$(<"$yay_log")"
grep -qF "Held AUR package 'bad'" "$test_tmp/add-output" || fail "AUR install reports the held package"
pass "AUR installs hold one failed item and continue the batch"

: >"$yay_log"
TEST_SCANS=1 omarchy-update-aur-pkgs >"$test_tmp/update-output" 2>&1
grep -qF "Held bad; continuing" "$test_tmp/update-output" || fail "AUR update does not report a held item"
grep -qF -- "--editor omarchy-pkg-aur-verify" "$yay_log" || fail "AUR update bypasses the verifier gate"
grep -qE -- '-S .* good$' "$yay_log" || fail "AUR update stops after a held package" "$(<"$yay_log")"
pass "AUR updates hold failures and continue with remaining packages"

for id in bad good; do
  dir="$test_tmp/$id"
  mkdir -p "$dir"
  printf 'pkgbase = %s\n' "$id" >"$dir/.SRCINFO"
  printf 'pkgname=%s\n' "$id" >"$dir/PKGBUILD"
  git -C "$dir" init -q
  git -C "$dir" add .
  git -C "$dir" -c user.name=Test -c user.email=test@example.com commit -qm Initial
done

: >"$review_log"
set +e
OMARCHY_SECURITY_UNATTENDED=1 omarchy-pkg-aur-verify \
  "$test_tmp/bad/PKGBUILD" "$test_tmp/good/PKGBUILD" >"$test_tmp/verify-output" 2>&1
status=$?
set -e
(( status != 0 )) || fail "unattended AUR verifier overrides a negative verdict"
[[ $(wc -l <"$review_log") == 2 ]] || fail "AUR verifier skips later transitive recipes" "$(<"$review_log")"
grep -qF -- "--revision" "$review_log" || fail "AUR verifier does not bind verdicts to a committed recipe"
grep -qF -- "--worktree" "$review_log" && fail "AUR verifier hashes generated build artifacts"
pass "AUR verifier scans every recipe and never overrides unattended"

printf 'changed after checkout\n' >>"$test_tmp/good/PKGBUILD"
: >"$review_log"
set +e
OMARCHY_SECURITY_UNATTENDED=1 omarchy-pkg-aur-verify "$test_tmp/good" >"$test_tmp/drift-output" 2>&1
status=$?
set -e
(( status != 0 )) || fail "AUR verifier accepts a tracked recipe that differs from its reviewed commit"
[[ ! -s $review_log ]] || fail "AUR verifier spends tokens on a recipe that already drifted"
grep -qF "tracked recipe differs" "$test_tmp/drift-output" || fail "AUR verifier does not explain recipe drift"
pass "AUR verifier rejects tracked recipe drift before spending agent tokens"
