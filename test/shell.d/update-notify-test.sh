#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
notify_log="$test_tmp/notify.log"
mkdir -p "$stub_bin" "$test_tmp/home/.hermes/hermes-agent/.git"

cat >"$stub_bin/checkupdates" <<'SH'
#!/bin/bash
case "${TEST_CHECKUPDATES:-none}" in
  updates)
    printf 'linux 6.1-1 -> 6.1-2\nfirefox 120-1 -> 120-2\n'
    exit 0
    ;;
  none)
    exit 2
    ;;
esac
SH
chmod +x "$stub_bin/checkupdates"

cat >"$stub_bin/yay" <<'SH'
#!/bin/bash
case "${TEST_AUR:-none}" in
  updates)
    printf 'spotify 1.0-1 -> 1.1-1\n'
    exit 0
    ;;
  none)
    exit 0
    ;;
esac
SH
chmod +x "$stub_bin/yay"

cat >"$stub_bin/mise" <<'SH'
#!/bin/bash
case "${TEST_MISE:-uptodate}" in
  updates)
    printf 'claude 2.1.260 -> 2.1.300\n'
    exit 0
    ;;
  uptodate)
    printf 'mise All tools are up to date\n'
    exit 0
    ;;
esac
SH
chmod +x "$stub_bin/mise"

cat >"$stub_bin/npm" <<'SH'
#!/bin/bash
case "${TEST_NPM:-none}" in
  updates)
    printf 'Package  Current   Wanted   Latest  Location              Depended by\nvercel    54.7.1   59.11.2  59.11.2  node_modules/vercel   global\n'
    exit 0
    ;;
  none)
    exit 0
    ;;
esac
SH
chmod +x "$stub_bin/npm"

cat >"$stub_bin/uv" <<'SH'
#!/bin/bash
case "${TEST_UV:-none}" in
  updates)
    printf 'litellm v1.99.0 -> v1.100.0\n'
    exit 0
    ;;
  none)
    exit 0
    ;;
esac
SH
chmod +x "$stub_bin/uv"

cat >"$stub_bin/git" <<'SH'
#!/bin/bash
[[ $1 == "-C" ]] || exit 1
shift 2
case "$1" in
  fetch) exit 0 ;;
  rev-list) printf '%s\n' "${TEST_HERMES_BEHIND:-0}" ;;
esac
SH
chmod +x "$stub_bin/git"

cat >"$stub_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$stub_bin/omarchy-cmd-present"

cat >"$stub_bin/omarchy-notification-send" <<SH
#!/bin/bash
printf '%s\n' "\$@" >>"$notify_log"
SH
chmod +x "$stub_bin/omarchy-notification-send"

export PATH="$stub_bin:$PATH"
export HOME="$test_tmp/home"

# Everything up to date -> no notification.
: >"$notify_log"
TEST_CHECKUPDATES=none TEST_AUR=none TEST_MISE=uptodate TEST_NPM=none TEST_UV=none TEST_HERMES_BEHIND=0 \
  "$ROOT/bin/omarchy-update-notify" || fail "notify exits successfully when up to date"
[[ ! -s $notify_log ]] || fail "notify stays quiet when up to date" "$(cat "$notify_log")"
pass "notify stays quiet when everything is up to date"

# Updates available -> sends a notification covering every source.
: >"$notify_log"
TEST_CHECKUPDATES=updates TEST_AUR=updates TEST_MISE=updates TEST_NPM=updates TEST_UV=updates TEST_HERMES_BEHIND=3 \
  "$ROOT/bin/omarchy-update-notify" || fail "notify exits successfully when updates are available"
grep -q 'Updates available' "$notify_log" || fail "notify sends an Updates available notification" "$(cat "$notify_log")"
grep -q 'system package' "$notify_log" || fail "notify reports system packages" "$(cat "$notify_log")"
grep -q 'AUR package' "$notify_log" || fail "notify reports AUR packages" "$(cat "$notify_log")"
grep -q 'mise tool' "$notify_log" || fail "notify reports mise tools" "$(cat "$notify_log")"
grep -q 'hermes agent' "$notify_log" || fail "notify reports hermes" "$(cat "$notify_log")"
grep -q 'npm global' "$notify_log" || fail "notify reports npm packages" "$(cat "$notify_log")"
grep -q 'uv tool' "$notify_log" || fail "notify reports uv tools" "$(cat "$notify_log")"
grep -q 'omarchy-update-menu' "$notify_log" || fail "notify click opens the update menu" "$(cat "$notify_log")"
pass "notify reports every update source and opens the menu on click"
