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

write_stub omarchy-update '#!/bin/bash
printf "update" >>"$OMARCHY_CHANNEL_TEST_LOG"
for arg in "$@"; do printf "\t%s" "$arg" >>"$OMARCHY_CHANNEL_TEST_LOG"; done
printf "\n" >>"$OMARCHY_CHANNEL_TEST_LOG"
'

write_stub gum '#!/bin/bash
printf "gum" >>"$OMARCHY_CHANNEL_TEST_LOG"
for arg in "$@"; do printf "\t%s" "$arg" >>"$OMARCHY_CHANNEL_TEST_LOG"; done
printf "\n" >>"$OMARCHY_CHANNEL_TEST_LOG"
if [[ $1 == "input" ]]; then
  printf "%s\n" "${OMARCHY_TEST_GUM_INPUT:-$HOME/Work/omarchy}"
fi
exit 0
'

write_stub omarchy-cmd-missing '#!/bin/bash
[[ $1 == "git" ]] && exit 1
exit 0
'

write_stub omarchy-cmd-present '#!/bin/bash
[[ $1 == "omarchy-dev-unlink" || $1 == "gum" || $1 == "git" ]] && exit 0
exit 1
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
    OMARCHY_EDGE_PATH="${OMARCHY_EDGE_PATH:-}" \
    OMARCHY_TEST_GUM_INPUT="${OMARCHY_TEST_GUM_INPUT:-}" \
    OMARCHY_PATH="$ROOT" \
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

assert_numbered_log_line() {
  local number="$1"
  local expected="$2"
  local description="$3"
  local actual=""

  actual=$(sed -n "${number}p" "$log_file")
  [[ $actual == $expected ]] || fail "$description" "$(cat "$log_file")"
  pass "$description"
}

run_channel stable
assert_log_line $'refresh\tstable' "stable refreshes the stable pacman channel"
assert_log_line $'sudo\tenv\tOMARCHY_UPDATE_PACMAN=1\tpacman\t-S\t--needed\t--noconfirm\t--ask\t4\tomarchy\tomarchy-settings' "stable installs stable Omarchy packages"
assert_log_line 'unlink' "stable restores the package-backed Omarchy path"
assert_log_line $'update\t-y' "stable runs the normal update pipeline"

run_channel dev
assert_log_line $'refresh\tedge' "dev refreshes the edge pacman channel"
assert_log_line $'sudo\tenv\tOMARCHY_UPDATE_PACMAN=1\tpacman\t-S\t--needed\t--noconfirm\t--ask\t4\tomarchy-dev\tomarchy-settings-dev' "dev installs development Omarchy packages"
assert_log_line 'unlink' "dev remains package-backed"

checkout="$test_tmp/edge-checkout"
default_checkout="$test_tmp/home/Work/omarchy"
OMARCHY_TEST_GUM_INPUT="$checkout" run_channel edge
assert_numbered_log_line 1 $'gum\tconfirm\t--default=false\tEnable Edge anyway?' "edge warns before changing packages"
assert_numbered_log_line 2 $'gum\tinput\t--value\t'"$default_checkout"$'\t--placeholder\t'"$default_checkout"$'\t--header\tWhere should Edge checkout live? Existing non-checkout paths will not be overwritten.' "edge prompts for the checkout path before changing packages"
assert_log_line $'gum\tconfirm\t--default=false\tEnable Edge anyway?' "edge asks for confirmation"
assert_log_line $'refresh\tedge' "edge refreshes the edge pacman channel"
assert_log_line $'sudo\tenv\tOMARCHY_UPDATE_PACMAN=1\tpacman\t-S\t--needed\t--noconfirm\t--ask\t4\tomarchy-dev\tomarchy-settings-dev' "edge installs development Omarchy packages"
assert_log_line $'git\tclone\t--branch\tquattro\t--single-branch\thttps://github.com/basecamp/omarchy.git\t'"$checkout" "edge clones the quattro checkout"
assert_log_line $'link\t'"$checkout" "edge links the source checkout"

occupied_checkout="$test_tmp/occupied"
mkdir -p "$occupied_checkout"
if OMARCHY_TEST_GUM_INPUT="$occupied_checkout" run_channel edge >"$test_tmp/occupied.out" 2>"$test_tmp/occupied.err"; then
  fail "edge refuses to use an occupied non-checkout path"
fi

grep -q "already exists and is not a git checkout" "$test_tmp/occupied.err" || fail "edge explains occupied checkout paths" "$(cat "$test_tmp/occupied.err")"
if grep -Fx $'refresh\tedge' "$log_file" >/dev/null; then
  fail "edge validates checkout path before changing packages" "$(cat "$log_file")"
fi
pass "edge refuses occupied non-checkout paths before package changes"

current_channel() {
  OMARCHY_TEST_VERSION_CHANNEL="$1" \
    OMARCHY_TEST_PACKAGES="$2" \
    OMARCHY_CONFIG_FILE="${3:-/dev/null}" \
    OMARCHY_PATH="${4:-/usr/share/omarchy}" \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-channel-current"
}

[[ $(current_channel stable stable) == "stable" ]] || fail "current channel detects stable"
pass "current channel detects stable"

[[ $(current_channel rc dev) == "rc" ]] || fail "current channel detects rc"
pass "current channel detects rc"

[[ $(current_channel edge dev /dev/null /usr/share/omarchy) == "dev" ]] || fail "current channel detects package-backed dev"
pass "current channel detects package-backed dev"

[[ $(current_channel edge dev /dev/null "$test_tmp/edge-checkout") == "edge" ]] || fail "current channel detects edge from OMARCHY_PATH"
pass "current channel detects edge from OMARCHY_PATH"

conf="$test_tmp/omarchy.conf"
printf 'export OMARCHY_PATH="%s"\n' "$test_tmp/edge-checkout" >"$conf"
[[ $(current_channel edge dev "$conf" /usr/share/omarchy) == "edge" ]] || fail "current channel detects edge from configured path"
pass "current channel detects edge from configured path"
