#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
runtime_dir="$test_tmp/runtime"
call_log="$test_tmp/calls"
marker="$runtime_dir/omarchy-hibernate-boot-auth.lock"
mkdir -p "$mock_bin" "$runtime_dir"

cat >"$mock_bin/omarchy-hibernation-boot-auth" <<'SH'
#!/bin/bash

exit "${BOOT_AUTH_STATUS:-1}"
SH

cat >"$mock_bin/systemctl" <<'SH'
#!/bin/bash

marker="$XDG_RUNTIME_DIR/omarchy-hibernate-boot-auth.lock"
marker_state=missing
if [[ -f $marker ]]; then
  exec 9<"$marker"
  flock -n -E 75 9 2>/dev/null
  lock_status=$?
  if (( lock_status == 75 )); then
    marker_state=locked
  else
    marker_state=unlocked
  fi
fi
printf 'systemctl %s marker=%s\n' "$*" "$marker_state" >>"$CALL_LOG"
exit "${SYSTEMCTL_STATUS:-0}"
SH
chmod +x "$mock_bin/omarchy-hibernation-boot-auth" "$mock_bin/systemctl"

run_hibernate() {
  : >"$call_log"
  set +e
  BOOT_AUTH_STATUS="$1" SYSTEMCTL_STATUS="${2:-0}" \
    XDG_RUNTIME_DIR="$runtime_dir" CALL_LOG="$call_log" PATH="$mock_bin:$PATH" \
    "$ROOT/bin/omarchy-system-hibernate"
  hibernate_status=$?
  set -e
}

run_hibernate 0
grep -Fx 'systemctl hibernate marker=locked' "$call_log" >/dev/null ||
  fail "encrypted hibernate marks boot-authenticated sleep"
pass "encrypted hibernate marks boot-authenticated sleep"

[[ ! -e $marker ]] || fail "encrypted hibernate cleans its marker after resume"
pass "encrypted hibernate cleans its marker after resume"

run_hibernate 1
grep -Fx 'systemctl hibernate marker=missing' "$call_log" >/dev/null ||
  fail "unencrypted hibernate leaves session locking enabled"
pass "unencrypted hibernate leaves session locking enabled"

run_hibernate 0 42
(( hibernate_status == 42 )) ||
  fail "hibernate propagates a failed system request" "exit: $hibernate_status"
[[ ! -e $marker ]] || fail "failed hibernate cleans its boot-auth marker"
pass "failed hibernate cleans its boot-auth marker"
