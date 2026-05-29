#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
test_home="$test_tmp/home"
state_home="$test_tmp/state"
mkdir -p "$stub_bin" "$test_home" "$state_home"

cat >"$stub_bin/fakeroot" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$stub_bin/fakeroot"

cat >"$stub_bin/checkupdates" <<'SH'
#!/bin/bash
case "${TEST_CHECKUPDATES:-updates}" in
  updates)
    printf 'linux 6.1-1 -> 6.1-2\nomarchy 4.0.0-1 -> 4.0.1-1\n'
    exit 0
    ;;
  none)
    exit 2
    ;;
  fail)
    echo "check failed" >&2
    exit 1
    ;;
esac
SH
chmod +x "$stub_bin/checkupdates"

cat >"$stub_bin/pacman" <<'SH'
#!/bin/bash
case "$1" in
  -Qem)
    [[ ${TEST_AUR_INSTALLED:-0} == "1" ]] && exit 0 || exit 1
    ;;
  -Qu)
    if [[ ${TEST_PACMAN_FALLBACK_UPDATES:-0} == "1" ]]; then
      echo "fallback-pkg 1-1 -> 1-2"
    fi
    exit 0
    ;;
esac
exit 0
SH
chmod +x "$stub_bin/pacman"

cat >"$stub_bin/yay" <<'SH'
#!/bin/bash
if [[ ${TEST_YAY_UPDATES:-0} == "1" ]]; then
  echo "aur-helper 1-1 -> 1-2"
fi
exit 0
SH
chmod +x "$stub_bin/yay"

run_checker() {
  HOME="$test_home" \
  XDG_STATE_HOME="$state_home" \
  PATH="$stub_bin:$PATH" \
  OMARCHY_UPDATE_CHECK_TIMEOUT=5 \
    "$ROOT/bin/omarchy-update-available"
}

capture_checker() {
  local stdout_file="$1"
  local stderr_file="$2"
  shift 2

  set +e
  (
    export "$@"
    run_checker
  ) >"$stdout_file" 2>"$stderr_file"
  local status=$?
  set -e
  return "$status"
}

stdout="$test_tmp/stdout"
stderr="$test_tmp/stderr"

if capture_checker "$stdout" "$stderr" TEST_CHECKUPDATES=updates TEST_AUR_INSTALLED=0; then
  status=0
else
  status=$?
fi
[[ $status -eq 0 ]] || fail "update checker exits successfully when system updates are available"
grep -q '^linux ' "$stdout" || fail "update checker prints system package updates"
grep -q '^omarchy ' "$state_home/omarchy/updates/packages" || fail "update checker stores system package updates"
[[ $(wc -l <"$state_home/omarchy/updates/available") -eq 2 ]] || fail "update checker stores combined update list"
pass "update checker detects system package updates"

if capture_checker "$stdout" "$stderr" TEST_CHECKUPDATES=none TEST_AUR_INSTALLED=1 TEST_YAY_UPDATES=1; then
  status=0
else
  status=$?
fi
[[ $status -eq 0 ]] || fail "update checker exits successfully when AUR updates are available"
grep -q '^aur-helper ' "$stdout" || fail "update checker prints AUR package updates"
grep -q '^aur-helper ' "$state_home/omarchy/updates/aur" || fail "update checker stores AUR package updates"
pass "update checker detects AUR package updates"

if capture_checker "$stdout" "$stderr" TEST_CHECKUPDATES=none TEST_AUR_INSTALLED=0; then
  status=0
else
  status=$?
fi
[[ $status -eq 1 ]] || fail "update checker exits non-zero when no updates are available"
grep -q '^System is up to date$' "$stdout" || fail "update checker prints up-to-date message"
[[ ! -s "$state_home/omarchy/updates/available" ]] || fail "update checker clears combined update list when up to date"
pass "update checker reports up-to-date systems"
