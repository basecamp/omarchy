#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

migration="$ROOT/migrations/1787865477.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

stub_bin="$test_dir/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/id" <<'STUB'
#!/bin/bash
printf '%s\n' "${STUB_GROUPS:-wheel}"
STUB
cat >"$stub_bin/pacman" <<'STUB'
#!/bin/bash
[[ $1 == "-Qq" ]] || exit 2
[[ " ${STUB_PACKAGES:-} " == *" $2 "* ]]
STUB
cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB
cat >"$stub_bin/gpasswd" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"${GPASSWD_CALLS:?}"
STUB
cat >"$stub_bin/omarchy-state" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"${STATE_CALLS:?}"
STUB
chmod +x "$stub_bin"/*

gpasswd_calls="$test_dir/gpasswd-calls"
state_calls="$test_dir/state-calls"

run_migration() {
  rm -f "$gpasswd_calls" "$state_calls"
  USER=tester STUB_GROUPS="$1" STUB_PACKAGES="${2:-}" \
    GPASSWD_CALLS="$gpasswd_calls" STATE_CALLS="$state_calls" \
    PATH="$stub_bin:$PATH" bash -euo pipefail "$migration"
}

run_migration "wheel input" >/dev/null
grep -qxF -- "-d tester input" "$gpasswd_calls" || fail "migration removes default input membership"
grep -qxF "set reboot-required" "$state_calls" || fail "migration flags the session change for reboot"
pass "migration removes the blanket input grant"

run_migration "wheel" >/dev/null
[[ ! -e $gpasswd_calls ]] || fail "migration does not remove an already-absent group"
[[ ! -e $state_calls ]] || fail "migration does not flag a reboot when nothing changed"
pass "migration is idempotent after input membership is gone"

run_migration "wheel input" xpadneo-dkms >/dev/null
[[ ! -e $gpasswd_calls ]] || fail "migration preserves input for controller support"
[[ ! -e $state_calls ]] || fail "preserved controller support does not flag a reboot"

run_migration "wheel input" ydotool >/dev/null
[[ ! -e $gpasswd_calls ]] || fail "migration preserves input for ydotool"
[[ ! -e $state_calls ]] || fail "preserved ydotool support does not flag a reboot"
pass "migration preserves deliberate input-group opt-ins"
