#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

update="$ROOT/bin/omarchy-update-system-pkgs"
retired_handler="$ROOT/bin/omarchy-update-system-pkgs-when-conflicted"

[[ ! -e $retired_handler ]] || fail "the automatic file-conflict handler is still shipped"
if /usr/bin/grep -ERq 'omarchy-update-system-pkgs-when-conflicted|OMARCHY_UPDATE_CONFLICT|OMARCHY_UPDATE_RETRY|OMARCHY_REPLACED_DIR' "$ROOT/bin"; then
  fail "the update commands still route into automatic file-conflict recovery"
fi
if /usr/bin/grep -q -- '--overwrite' "$update"; then
  fail "normal package updates still use Pacman's overwrite escape hatch"
fi
pass "normal package updates never use Pacman's overwrite escape hatch"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin" "$test_tmp/tmp"

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$SUDO_CALLS"

expected='/usr/bin/env LC_ALL=C OMARCHY_UPDATE_PACMAN=1 /usr/bin/pacman -Syu --noconfirm'
if [[ $* != "$expected" ]]; then
  echo "unexpected privileged command: $*" >&2
  exit 97
fi

exec "$PACMAN_STUB" -Syu --noconfirm
STUB

cat >"$stub_bin/pacman-stub" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$PACMAN_CALLS"

if [[ $PACMAN_CASE == "file-conflict" ]]; then
  echo 'error: failed to commit transaction (conflicting files)' >&2
  echo "omarchy-settings: $CONFLICT_PATH exists in filesystem" >&2
  exit 42
fi

echo 'upgrade complete'
STUB

for command in omarchy-update-system-pkgs-when-conflicted mv mkdir; do
  cat >"$stub_bin/$command" <<'STUB'
#!/bin/bash
printf '%s\n' "${0##*/} $*" >>"$POISON_CALLS"
exit 96
STUB
done

chmod +x "$stub_bin"/*

run_update() {
  PACMAN_CASE="$1" \
    PACMAN_STUB="$stub_bin/pacman-stub" \
    PACMAN_CALLS="$test_tmp/pacman-calls" \
    SUDO_CALLS="$test_tmp/sudo-calls" \
    POISON_CALLS="$test_tmp/poison-calls" \
    CONFLICT_PATH="$test_tmp/live.conf" \
    TMPDIR="$test_tmp/tmp" \
    OMARCHY_REPLACED_DIR="$test_tmp/replaced" \
    OMARCHY_UPDATE_CONFLICT=1 \
    OMARCHY_UPDATE_RETRY=1 \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    bash "$update"
}

: >"$test_tmp/pacman-calls"
: >"$test_tmp/sudo-calls"
: >"$test_tmp/poison-calls"
run_update clean >"$test_tmp/out" 2>"$test_tmp/err" || fail "a clean package update fails"
[[ $(wc -l <"$test_tmp/pacman-calls") == 1 ]] || fail "a clean package update runs more than one transaction"
[[ $(<"$test_tmp/pacman-calls") == "-Syu --noconfirm" ]] || fail "a clean package update changes Pacman's ordinary arguments"
[[ ! -s $test_tmp/poison-calls ]] || fail "a clean package update reaches retired recovery commands"
[[ -z $(find "$test_tmp/tmp" -mindepth 1 -print -quit) ]] || fail "a clean package update leaks its error report"
pass "clean package updates run one ordinary transaction"

printf 'original contents\n' >"$test_tmp/live.conf"
original_inode=$(stat -c %i "$test_tmp/live.conf")
: >"$test_tmp/pacman-calls"
: >"$test_tmp/sudo-calls"
: >"$test_tmp/poison-calls"

if run_update file-conflict >"$test_tmp/out" 2>"$test_tmp/err"; then
  fail "a filesystem conflict passes for a successful update"
else
  update_status=$?
fi

((update_status == 42)) || fail "a filesystem conflict does not preserve Pacman's status"
[[ $(wc -l <"$test_tmp/pacman-calls") == 1 ]] || fail "a filesystem conflict retries Pacman"
[[ $(wc -l <"$test_tmp/sudo-calls") == 1 ]] || fail "a filesystem conflict authorizes another privileged command"
[[ ! -s $test_tmp/poison-calls ]] || fail "a filesystem conflict reaches a mover or retired handler"
[[ $(stat -c %i "$test_tmp/live.conf") == "$original_inode" ]] || fail "a filesystem conflict replaces the live path"
/usr/bin/grep -qx 'original contents' "$test_tmp/live.conf" || fail "a filesystem conflict changes the live path"
[[ ! -e $test_tmp/replaced ]] || fail "a filesystem conflict creates a quarantine"
/usr/bin/grep -q 'exists in filesystem' "$test_tmp/err" || fail "Pacman's filesystem-conflict report is hidden"
[[ -z $(find "$test_tmp/tmp" -mindepth 1 -print -quit) ]] || fail "a failed package update leaks its error report"
pass "filesystem conflicts fail once without moving or archiving live paths"
