#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

if [[ ${OMARCHY_CHANNEL_TEST_NS:-0} != 1 ]]; then
  exec unshare --user --map-root-user --mount \
    env OMARCHY_CHANNEL_TEST_NS=1 bash "$0"
fi

test_tmp=$(mktemp -d)
fixed_paths_bound=0
sudo_wrapper_tree_bound=0
cleanup() {
  if (( fixed_paths_bound )); then
    umount /usr/bin/gum
    umount /usr/bin/git
    umount /usr/bin/omarchy-dev-link
    umount /usr/bin/omarchy-dev-unlink
    umount /usr/bin/omarchy-state
    umount /usr/bin/omarchy-refresh-pacman
    umount /usr/bin/omarchy-update
    umount /usr/bin/sudo
  fi
  if (( sudo_wrapper_tree_bound )); then
    umount /usr/share/omarchy
  fi
  rm -rf "$test_tmp"
}
trap cleanup EXIT

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
if [[ ${1:-} == "--run-deferred-hook" ]]; then
  omarchy-hook pre-refresh-pacman
fi
'

write_stub sudo '#!/bin/bash
printf "sudo" >>"$OMARCHY_CHANNEL_TEST_LOG"
for arg in "$@"; do printf "\t%s" "$arg" >>"$OMARCHY_CHANNEL_TEST_LOG"; done
printf "\n" >>"$OMARCHY_CHANNEL_TEST_LOG"
if [[ ${1:-} == "-h" ]]; then
  echo "usage: sudo [-ABbEHkNnPS] command"
fi
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
printf "\tOMARCHY_PATH=%s" "$OMARCHY_PATH" >>"$OMARCHY_CHANNEL_TEST_LOG"
printf "\n" >>"$OMARCHY_CHANNEL_TEST_LOG"
exit "${OMARCHY_TEST_UPDATE_STATUS:-0}"
'

write_stub omarchy-hook '#!/bin/bash
printf "hook" >>"$OMARCHY_CHANNEL_TEST_LOG"
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

# Channel-set deliberately invokes the three trust-boundary commands through
# fixed installed paths. Bind the stubs over those paths only in this private
# mount namespace so the behavior tests exercise that contract.
mount -t tmpfs -o mode=0755 tmpfs /usr/share/omarchy
mkdir -p /usr/share/omarchy/default/omarchy/sudo-no-update
cp "$ROOT/default/omarchy/sudo-no-update/sudo" /usr/share/omarchy/default/omarchy/sudo-no-update/sudo
chmod 0755 /usr/share/omarchy/default/omarchy/sudo-no-update/sudo
sudo_wrapper_tree_bound=1
mount --bind "$stub_bin/gum" /usr/bin/gum
mount --bind "$stub_bin/git" /usr/bin/git
mount --bind "$stub_bin/omarchy-dev-link" /usr/bin/omarchy-dev-link
mount --bind "$stub_bin/omarchy-dev-unlink" /usr/bin/omarchy-dev-unlink
mount --bind "$stub_bin/omarchy-state" /usr/bin/omarchy-state
mount --bind "$stub_bin/omarchy-refresh-pacman" /usr/bin/omarchy-refresh-pacman
mount --bind "$stub_bin/omarchy-update" /usr/bin/omarchy-update
mount --bind "$stub_bin/sudo" /usr/bin/sudo
fixed_paths_bound=1

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
assert_log_line $'refresh\tstable\t--defer-hook' "stable refreshes the stable pacman channel with its user hook deferred"
assert_log_line $'sudo\t-N\t--\t/usr/bin/env\tPATH=/usr/bin:/usr/sbin:/bin:/sbin\tOMARCHY_UPDATE_PACMAN=1\t/usr/bin/pacman\t-S\t--needed\t--noconfirm\t--ask\t4\tomarchy\tomarchy-settings' "stable installs stable Omarchy packages without publishing a timestamp"
assert_log_line $'unlink\t--no-reboot' "stable restores the package-backed Omarchy path without an early reboot prompt"
assert_log_line $'update\t-y\tOMARCHY_PATH=/usr/share/omarchy' "stable runs the normal update pipeline from the package-backed path"
assert_log_line $'refresh\t--run-deferred-hook' "stable reaches the deferred refresh-hook boundary after updating"
assert_log_line $'hook\tpre-refresh-pacman' "stable runs the deferred refresh hook exactly once"
[[ $(grep -c $'^hook\tpre-refresh-pacman$' "$log_file") == 1 ]] || fail "stable ran the deferred refresh hook more than once" "$(cat "$log_file")"
if grep -q $'^state\tset\treboot-required$' "$log_file"; then
  fail "stable does not require reboot when already package-backed" "$(cat "$log_file")"
fi
pass "stable does not require reboot when already package-backed"

run_channel rc
assert_log_line $'refresh\trc\t--defer-hook' "rc refreshes the rc pacman channel"
assert_log_line $'sudo\t-N\t--\t/usr/bin/env\tPATH=/usr/bin:/usr/sbin:/bin:/sbin\tOMARCHY_UPDATE_PACMAN=1\t/usr/bin/pacman\t-S\t--needed\t--noconfirm\t--ask\t4\tomarchy\tomarchy-settings' "rc installs rc Omarchy packages"
assert_log_line $'unlink\t--no-reboot' "rc restores the package-backed Omarchy path without an early reboot prompt"
assert_log_line $'update\t-y\tOMARCHY_PATH=/usr/share/omarchy' "rc runs the normal update pipeline from the package-backed path"

OMARCHY_TEST_PATH="$ROOT" run_channel edge
assert_log_line $'refresh\tedge\t--defer-hook' "edge refreshes the edge pacman channel"
assert_log_line $'sudo\t-N\t--\t/usr/bin/env\tPATH=/usr/bin:/usr/sbin:/bin:/sbin\tOMARCHY_UPDATE_PACMAN=1\t/usr/bin/pacman\t-S\t--needed\t--noconfirm\t--ask\t4\tomarchy-dev\tomarchy-settings-dev' "edge installs development Omarchy packages"
assert_log_line $'unlink\t--no-reboot' "edge unlinks dev without an early reboot prompt"
assert_log_line $'state\tset\treboot-required' "edge marks reboot required when leaving dev"
assert_log_line $'update\t-y\tOMARCHY_PATH=/usr/share/omarchy' "edge runs the normal update pipeline from the package-backed path"
[[ $(grep -E '^(unlink|state|update)' "$log_file") == $'unlink\t--no-reboot\nstate\tset\treboot-required\nupdate\t-y\tOMARCHY_PATH=/usr/share/omarchy' ]] ||
  fail "edge defers the reboot prompt until the update restart stage" "$(cat "$log_file")"
pass "edge defers the reboot prompt until the update restart stage"

checkout="$test_tmp/home/omarchy"
mkdir -p "$checkout"
if run_channel dev >"$test_tmp/occupied.out" 2>"$test_tmp/occupied.err"; then
  fail "dev refuses to use an occupied non-checkout path"
fi

grep -q "already exists and is not a git checkout" "$test_tmp/occupied.err" || fail "dev explains occupied checkout paths" "$(cat "$test_tmp/occupied.err")"
if grep -Fx $'refresh\tedge\t--defer-hook' "$log_file" >/dev/null; then
  fail "dev validates checkout path before changing packages" "$(cat "$log_file")"
fi
pass "dev refuses occupied non-checkout paths before package changes"

rmdir "$checkout"
run_channel dev
assert_log_line $'gum\tconfirm\t--default=false\tSwitch to dev channel?' "dev asks for confirmation"
assert_log_line $'refresh\tedge\t--defer-hook' "dev refreshes the edge pacman channel"
assert_log_line $'sudo\t-N\t--\t/usr/bin/env\tPATH=/usr/bin:/usr/sbin:/bin:/sbin\tOMARCHY_UPDATE_PACMAN=1\t/usr/bin/pacman\t-S\t--needed\t--noconfirm\t--ask\t4\tomarchy-dev\tomarchy-settings-dev' "dev installs development Omarchy packages"
assert_log_line $'git\tclone\thttps://github.com/basecamp/omarchy.git\t'"$checkout" "dev clones the source checkout to ~/omarchy"
assert_log_line $'link\t'"$checkout"$'\t--no-reboot' "dev links ~/omarchy without an early reboot prompt"
assert_log_line $'state\tset\treboot-required' "dev defers the reboot prompt to the update pipeline"
assert_log_line $'update\t-y\tOMARCHY_PATH='"$checkout" "dev runs the normal update pipeline from the source checkout"
[[ $(grep -E '^(git|link|state|refresh|sudo[[:space:]]-N|update|hook)' "$log_file") == $'git\tclone\thttps://github.com/basecamp/omarchy.git\t'"$checkout"$'\nlink\t'"$checkout"$'\t--no-reboot\nstate\tset\treboot-required\nrefresh\tedge\t--defer-hook\nsudo\t-N\t--\t/usr/bin/env\tPATH=/usr/bin:/usr/sbin:/bin:/sbin\tOMARCHY_UPDATE_PACMAN=1\t/usr/bin/pacman\t-S\t--needed\t--noconfirm\t--ask\t4\tomarchy-dev\tomarchy-settings-dev\nupdate\t-y\tOMARCHY_PATH='"$checkout"$'\nrefresh\t--run-deferred-hook\nhook\tpre-refresh-pacman' ]] ||
  fail "dev activates the checkout before changing or updating packages" "$(cat "$log_file")"
pass "dev activates the checkout before changing or updating packages"

OMARCHY_TEST_PATH="$checkout" run_channel stable
assert_log_line $'unlink\t--no-reboot' "switching from dev to stable unlinks without an early reboot prompt"
assert_log_line $'state\tset\treboot-required' "switching from dev to stable marks reboot required"

run_channel dev
if grep -q $'^git\tclone\t' "$log_file"; then
  fail "dev reuses an existing checkout" "$(cat "$log_file")"
fi
assert_log_line $'link\t'"$checkout"$'\t--no-reboot' "switching back to dev links ~/omarchy"
pass "switching back to dev reuses the existing ~/omarchy checkout"

OMARCHY_TEST_UPDATE_STATUS=1
export OMARCHY_TEST_UPDATE_STATUS
if run_channel stable >"$test_tmp/update-fail.out" 2>"$test_tmp/update-fail.err"; then
  fail "channel switch with a failed update unexpectedly succeeded"
fi
unset OMARCHY_TEST_UPDATE_STATUS
if grep -qxF $'refresh\t--run-deferred-hook' "$log_file" ||
  grep -qxF $'hook\tpre-refresh-pacman' "$log_file"; then
  fail "failed channel update ran the deferred refresh hook" "$(cat "$log_file")"
fi
grep -qxF $'sudo\t-k' "$log_file" || fail "failed channel update did not invalidate sudo credentials" "$(cat "$log_file")"
pass "failed channel updates invalidate credentials and skip the deferred hook"

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
