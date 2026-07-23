#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
log_file="$test_tmp/channel.log"
mkdir -p "$stub_bin" "$test_tmp/home"

write_stub() {
  local name="$1"
  local body="$2"

  cat >"$stub_bin/$name" <<<"$body"
  chmod +x "$stub_bin/$name"
}

write_stub omarchy-refresh-pacman '#!/bin/bash
printf "refresh" >>"$OMARCHY_CHANNEL_TEST_LOG"
for arg in "$@"; do printf "\t%s" "$arg" >>"$OMARCHY_CHANNEL_TEST_LOG"; done
printf "\n" >>"$OMARCHY_CHANNEL_TEST_LOG"
'

write_stub sudo '#!/bin/bash
printf "sudo" >>"$OMARCHY_CHANNEL_TEST_LOG"
for arg in "$@"; do printf "\t%s" "$arg" >>"$OMARCHY_CHANNEL_TEST_LOG"; done
printf "\n" >>"$OMARCHY_CHANNEL_TEST_LOG"
'

write_stub omarchy-dev-unlink '#!/bin/bash
printf "unlink" >>"$OMARCHY_CHANNEL_TEST_LOG"
for arg in "$@"; do printf "\t%s" "$arg" >>"$OMARCHY_CHANNEL_TEST_LOG"; done
printf "\n" >>"$OMARCHY_CHANNEL_TEST_LOG"
'

write_stub omarchy-state '#!/bin/bash
printf "state" >>"$OMARCHY_CHANNEL_TEST_LOG"
for arg in "$@"; do printf "\t%s" "$arg" >>"$OMARCHY_CHANNEL_TEST_LOG"; done
printf "\n" >>"$OMARCHY_CHANNEL_TEST_LOG"
'

write_stub omarchy-update '#!/bin/bash
printf "update" >>"$OMARCHY_CHANNEL_TEST_LOG"
for arg in "$@"; do printf "\t%s" "$arg" >>"$OMARCHY_CHANNEL_TEST_LOG"; done
printf "\n" >>"$OMARCHY_CHANNEL_TEST_LOG"
'

write_stub gum '#!/bin/bash
printf "gum" >>"$OMARCHY_CHANNEL_TEST_LOG"
for arg in "$@"; do printf "\t%s" "$arg" >>"$OMARCHY_CHANNEL_TEST_LOG"; done
printf "\n" >>"$OMARCHY_CHANNEL_TEST_LOG"
exit 0
'

write_stub git '#!/bin/bash
printf "git" >>"$OMARCHY_CHANNEL_TEST_LOG"
for arg in "$@"; do printf "\t%s" "$arg" >>"$OMARCHY_CHANNEL_TEST_LOG"; done
printf "\n" >>"$OMARCHY_CHANNEL_TEST_LOG"
if [[ $1 == "clone" ]]; then
  dest="${@: -1}"
  mkdir -p "$dest/.git" "$dest/bin" "$dest/default" "$dest/shell"
fi
'

write_stub omarchy-dev-link '#!/bin/bash
printf "link" >>"$OMARCHY_CHANNEL_TEST_LOG"
for arg in "$@"; do printf "\t%s" "$arg" >>"$OMARCHY_CHANNEL_TEST_LOG"; done
printf "\n" >>"$OMARCHY_CHANNEL_TEST_LOG"
'

write_stub omarchy-version-channel '#!/bin/bash
printf "%s\n" "${OMARCHY_TEST_VERSION_CHANNEL:-unknown}"
'

write_stub pacman '#!/bin/bash
[[ $1 == "-Q" ]] || exit 1
shift
case "${OMARCHY_TEST_PACKAGES:-}" in
  stable) [[ $* == "omarchy omarchy-settings" ]] ;;
  dev) [[ $* == "omarchy-dev omarchy-settings-dev" ]] ;;
  *) exit 1 ;;
esac
'

run_channel() {
  : >"$log_file"
  OMARCHY_CHANNEL_TEST_LOG="$log_file" \
    OMARCHY_PATH="${OMARCHY_TEST_PATH:-/usr/share/omarchy}" \
    HOME="$test_tmp/home" \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-channel-set" "$@"
}

assert_log_line() {
  local expected="$1"
  local description="$2"

  grep -Fx -- "$expected" "$log_file" >/dev/null || fail "$description" "$(cat "$log_file")"
  pass "$description"
}

run_channel stable
assert_log_line $'refresh\tstable' "stable refreshes the stable pacman channel"
assert_log_line $'sudo\tenv\tOMARCHY_UPDATE_PACMAN=1\tpacman\t-S\t--needed\t--noconfirm\t--ask\t4\tomarchy\tomarchy-settings' "stable installs stable Omarchy packages"
assert_log_line $'unlink\t--no-reboot' "stable restores the package-backed Omarchy path without an early reboot prompt"
assert_log_line $'update\t-y' "stable runs the normal update pipeline"
if grep -q $'^state\tset\treboot-required$' "$log_file"; then
  fail "stable does not require reboot when already package-backed" "$(cat "$log_file")"
fi
pass "stable does not require reboot when already package-backed"

run_channel rc
assert_log_line $'refresh\trc' "rc refreshes the rc pacman channel"
assert_log_line $'sudo\tenv\tOMARCHY_UPDATE_PACMAN=1\tpacman\t-S\t--needed\t--noconfirm\t--ask\t4\tomarchy\tomarchy-settings' "rc installs rc Omarchy packages"
assert_log_line $'unlink\t--no-reboot' "rc restores the package-backed Omarchy path without an early reboot prompt"
assert_log_line $'update\t-y' "rc runs the normal update pipeline"

OMARCHY_TEST_PATH="$ROOT" run_channel edge
assert_log_line $'refresh\tedge' "edge refreshes the edge pacman channel"
assert_log_line $'sudo\tenv\tOMARCHY_UPDATE_PACMAN=1\tpacman\t-S\t--needed\t--noconfirm\t--ask\t4\tomarchy-dev\tomarchy-settings-dev' "edge installs development Omarchy packages"
assert_log_line $'unlink\t--no-reboot' "edge unlinks dev without an early reboot prompt"
assert_log_line $'state\tset\treboot-required' "edge marks reboot required when leaving dev"
assert_log_line $'update\t-y' "edge runs the normal update pipeline"
[[ $(grep -E '^(unlink|state|update)' "$log_file") == $'unlink\t--no-reboot\nstate\tset\treboot-required\nupdate\t-y' ]] ||
  fail "edge defers the reboot prompt until the update restart stage" "$(cat "$log_file")"
pass "edge defers the reboot prompt until the update restart stage"

checkout="$test_tmp/home/omarchy"
mkdir -p "$checkout"
if run_channel dev >"$test_tmp/occupied.out" 2>"$test_tmp/occupied.err"; then
  fail "dev refuses to use an occupied non-checkout path"
fi

grep -q "already exists and is not a git checkout" "$test_tmp/occupied.err" || fail "dev explains occupied checkout paths" "$(cat "$test_tmp/occupied.err")"
if grep -Fx $'refresh\tedge' "$log_file" >/dev/null; then
  fail "dev validates checkout path before changing packages" "$(cat "$log_file")"
fi
pass "dev refuses occupied non-checkout paths before package changes"

rmdir "$checkout"
run_channel dev
assert_log_line $'gum\tconfirm\t--default=false\tEnable Dev anyway?' "dev asks for confirmation"
assert_log_line $'refresh\tedge' "dev refreshes the edge pacman channel"
assert_log_line $'sudo\tenv\tOMARCHY_UPDATE_PACMAN=1\tpacman\t-S\t--needed\t--noconfirm\t--ask\t4\tomarchy-dev\tomarchy-settings-dev' "dev installs development Omarchy packages"
assert_log_line $'git\tclone\thttps://github.com/basecamp/omarchy.git\t'"$checkout" "dev clones the source checkout to ~/omarchy"
assert_log_line $'link\t'"$checkout" "dev links ~/omarchy"

OMARCHY_TEST_PATH="$checkout" run_channel stable
assert_log_line $'unlink\t--no-reboot' "switching from dev to stable unlinks without an early reboot prompt"
assert_log_line $'state\tset\treboot-required' "switching from dev to stable marks reboot required"

run_channel dev
if grep -q $'^git\tclone\t' "$log_file"; then
  fail "dev reuses an existing checkout" "$(cat "$log_file")"
fi
assert_log_line $'link\t'"$checkout" "switching back to dev links ~/omarchy"
pass "switching back to dev reuses the existing ~/omarchy checkout"

current_channel() {
  OMARCHY_TEST_VERSION_CHANNEL="$1" \
    OMARCHY_TEST_PACKAGES="$2" \
    OMARCHY_PATH="$3" \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-channel-current"
}

[[ $(current_channel stable stable /usr/share/omarchy) == "stable" ]] || fail "current channel detects stable"
pass "current channel detects stable"

[[ $(current_channel rc stable /usr/share/omarchy) == "rc" ]] || fail "current channel detects rc"
pass "current channel detects rc"

[[ $(current_channel edge dev /usr/share/omarchy) == "edge" ]] || fail "current channel detects package-backed edge"
pass "current channel detects package-backed edge"

[[ $(current_channel edge dev "$test_tmp/dev-checkout") == "dev" ]] || fail "current channel detects dev from OMARCHY_PATH"
pass "current channel honors a dev link outside ~/omarchy"
