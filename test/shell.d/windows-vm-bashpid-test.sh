#!/bin/bash

# $BASHPID inside a command substitution is the subshell PID, not the parent.
# omarchy-windows-vm pins directories via /proc/$BASHPID/fd/N; reading that path
# from $(stat ...) looked at the wrong process and made the 0700 privacy check
# fail closed after a correct chmod (#10035).

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

vm="$ROOT/bin/omarchy-windows-vm"

# Production script must snapshot BASHPID before any $(...) that touches
# /proc/<pid>/fd, and must not expand bare $BASHPID inside command substitutions.
if grep -nE '\$\([^)]*\$BASHPID' "$vm" >/dev/null; then
  fail "omarchy-windows-vm must not expand \$BASHPID inside \$(...)"
fi

# prepare_caller_mounts / open_mount_source / pinned_* / bind_mount_leaf each
# capture self_pid before fd walks.
for fn in open_mount_source pinned_dir_contains pinned_tree_contains bind_mount_leaf prepare_caller_mounts; do
  block=$(awk -v fn="$fn" '
    $0 ~ "^" fn "\\(\\)" { printing = 1 }
    printing { print }
    printing && /^}$/ { exit }
  ' "$vm")
  [[ $block == *"local self_pid=\$BASHPID"* ]] ||
    fail "$fn snapshots BASHPID into self_pid before /proc fd access"
done
pass "mount helpers snapshot BASHPID before command substitutions"

# Runtime demonstration of the language trap. Bash 3 (macOS host) has no
# BASHPID and no /proc; Omarchy targets bash 5 on Linux, so skip the live probe
# when the host cannot express the bug.
if ! bash -c '[[ -n ${BASHPID+x} ]]' 2>/dev/null; then
  pass "host bash has no BASHPID; static snapshot checks cover the regression"
  exit 0
fi

# shellcheck disable=SC2034
parent_pid=$(bash -c 'echo "$BASHPID"')
sub_pid=$(bash -c 'echo "$(echo "$BASHPID")"')
# In bash -c 'echo "$(echo "$BASHPID")"' both layers are nested; use a single
# script that prints parent then subshell BASHPID.
read -r parent_pid sub_pid < <(bash -c 'p=$BASHPID; s=$(echo $BASHPID); echo "$p $s"')
[[ $parent_pid != "$sub_pid" ]] ||
  fail "precondition: BASHPID inside \$(...) differs from parent" \
    "parent=$parent_pid sub=$sub_pid"
pass "BASHPID inside command substitution is a different process"

if [[ ! -d /proc/self/fd ]]; then
  pass "no /proc; BASHPID divergence check covers the language trap"
  exit 0
fi

# On Linux, prove the fixed pattern: snapshot, then stat via /proc/$self_pid/fd.
bash <<'PROBE' || fail "self_pid snapshot reads the parent descriptor table"
set -euo pipefail
self_pid=$BASHPID
exec {demo_fd}</ || exit 1
mode=$(stat -Lc '%a' "/proc/$self_pid/fd/$demo_fd" 2>/dev/null) || mode=""
exec {demo_fd}<&-
[[ $mode =~ ^[0-7]{3,4}$ ]] || exit 1
PROBE
pass "stat via self_pid hits the parent descriptor table"
