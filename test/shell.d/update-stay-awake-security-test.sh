#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
test_processes=()
test_runtime_created=""
cleanup_test() {
  for pid in "${test_processes[@]}"; do kill "$pid" 2>/dev/null || true; done
  [[ -z ${state_dir:-} ]] || rm -rf -- "$state_dir"
  [[ -z ${state_hardlink:-} ]] || rm -f -- "$state_hardlink"
  rm -rf -- "$test_tmp"
  [[ -z $test_runtime_created ]] || rmdir -- "$test_runtime_created" 2>/dev/null || true
}
trap cleanup_test EXIT

stub_bin="$test_tmp/bin"
test_home="$test_tmp/home"
runtime_dir=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
if [[ ! -d $runtime_dir || -L $runtime_dir || $(stat -Lc '%u %a' "$runtime_dir" 2>/dev/null || true) != "$(id -u) 700" ]]; then
  if (( EUID != 0 )); then
    fail "test needs a private XDG runtime directory or root namespace"
  fi
  runtime_dir=$(mktemp -d -p /run omarchy-stay-awake-runtime.XXXXXXXX)
  chmod 0700 "$runtime_dir"
  test_runtime_created="$runtime_dir"
fi
test_run_id="test-$BASHPID-$RANDOM"
state_dir="$runtime_dir/omarchy-update-stay-awake-$test_run_id"
state_hardlink="$runtime_dir/.omarchy-update-stay-awake-hardlink-$test_run_id"
inhibitor_log="$test_tmp/inhibitors"
mkdir -p "$stub_bin" "$test_home"
: >"$inhibitor_log"

cat >"$stub_bin/pkexec" <<'SH'
#!/bin/bash
exec "$@"
SH

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
[[ ${1:-} == "-v" ]] && exit 0
exec "$@"
SH

cat >"$stub_bin/systemd-inhibit" <<'SH'
#!/bin/bash
[[ ${SYSTEMD_FAIL:-0} == "0" ]] || exit 42
printf '%s\n' "$$" >>"$INHIBITOR_LOG"
if [[ -n ${CREATE_BAD_IDLE:-} ]]; then
  ln -s "$CREATE_BAD_IDLE" "$TEST_STATE_DIR/idle-owner"
fi
trap 'exit 0' TERM
while :; do
  sleep 0.05
done
SH

cat >"$stub_bin/omarchy-toggle-idle" <<'SH'
#!/bin/bash
state_file="$HOME/.local/state/omarchy/indicators/stay-awake"
case "$1" in
  stay-awake)
    mkdir -p "$(dirname "$state_file")"
    touch "$state_file"
    ;;
  allow-idle)
    rm -f "$state_file"
    ;;
esac
SH
chmod +x "$stub_bin"/*

mapped_helper="$test_tmp/omarchy-update-stay-awake"
sed \
  -e 's#state_dir="$state_base/omarchy-update-stay-awake"#state_dir="$state_base/omarchy-update-stay-awake-${OMARCHY_TEST_RUN_ID:?}"#' \
  "$ROOT/bin/omarchy-update-stay-awake" >"$mapped_helper"
chmod +x "$mapped_helper"

run_helper() {
  HOME="$test_home" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  INHIBITOR_LOG="$inhibitor_log" \
  TEST_STATE_DIR="$state_dir" \
  OMARCHY_TEST_RUN_ID="$test_run_id" \
  PATH="$stub_bin:$ROOT/bin:/usr/bin:/bin" \
    "$mapped_helper" "$@"
}

wait_dead() {
  local pid="$1"

  for _ in {1..100}; do
    kill -0 "$pid" 2>/dev/null || return 0
    [[ $(awk '{ print $3 }' "/proc/$pid/stat" 2>/dev/null || true) == "Z" ]] && return 0
    sleep 0.02
  done
  return 1
}

prepare_state_dir() {
  rm -rf "$state_dir"
  mkdir -m 700 "$state_dir"
}

write_inhibit_state() {
  local record="$1"

  printf '%s\n' "$record" >"$state_dir/inhibit-pid"
  chmod 600 "$state_dir/inhibit-pid"
}

start_identity_process() {
  local token="$1"

  /usr/bin/bash -c 'trap "exit 0" TERM; while :; do sleep 0.05; done' \
    omarchy-test "--why=Omarchy update in progress [$token]" &
  identity_pid=$!
  test_processes+=("$identity_pid")
  identity_start=$(awk '{ print $22 }' "/proc/$identity_pid/stat")
  identity_owner=$(stat -Lc '%u' "/proc/$identity_pid")
}

unverified_signals=$(grep -nE '(^|[[:space:]])kill ([^-]|-[^0])[^#]*\$inhibit_pid' \
  "$ROOT/bin/omarchy-update-stay-awake" || true)
if [[ -n $unverified_signals ]]; then
  fail "inhibitor signals bypass identity verification" "$unverified_signals"
fi
grep -q 'signal_inhibitor .* KILL' "$ROOT/bin/omarchy-update-stay-awake" ||
  fail "delayed inhibitor cleanup revalidates the full identity before KILL"
pass "every inhibitor signal is identity-bound"

run_helper start
[[ -s $state_dir/inhibit-pid ]] || fail "valid XDG runtime publishes inhibitor state"
read -r version valid_pid valid_start valid_owner valid_token <"$state_dir/inhibit-pid"
[[ $version == "1" && $valid_token =~ ^[0-9a-f]{32}$ ]] || fail "inhibitor state is an exact versioned identity"
[[ $(stat -Lc '%u %a %h' "$state_dir/inhibit-pid") == "$(id -u) 600 1" ]] ||
  fail "inhibitor state is private, caller-owned, and singly linked"
run_helper stop
wait_dead "$valid_pid" || fail "valid inhibitor identity is stopped"
[[ ! -e $state_dir ]] || fail "valid state is cleaned after stop"
pass "valid XDG runtime uses private atomic inhibitor state"

permissive_runtime="$test_tmp/permissive-runtime"
mkdir -m 755 "$permissive_runtime"
if HOME="$test_home" XDG_RUNTIME_DIR="$permissive_runtime" PATH="$stub_bin:$ROOT/bin:/usr/bin:/bin" \
  OMARCHY_TEST_RUN_ID="$test_run_id" "$mapped_helper" stop 2>/dev/null; then
  fail "permissive XDG runtime is rejected"
fi
symlink_runtime="$test_tmp/runtime-link"
ln -s "$runtime_dir" "$symlink_runtime"
if HOME="$test_home" XDG_RUNTIME_DIR="$symlink_runtime" PATH="$stub_bin:$ROOT/bin:/usr/bin:/bin" \
  OMARCHY_TEST_RUN_ID="$test_run_id" "$mapped_helper" stop 2>/dev/null; then
  fail "symlink XDG runtime is rejected"
fi
if HOME="$test_home" XDG_RUNTIME_DIR="$test_tmp/../${test_tmp##*/}/runtime" PATH="$stub_bin:$ROOT/bin:/usr/bin:/bin" \
  OMARCHY_TEST_RUN_ID="$test_run_id" "$mapped_helper" stop 2>/dev/null; then
  fail "non-canonical XDG runtime is rejected"
fi
pass "unsafe XDG runtime directories are rejected"

mkdir -m 700 "$test_tmp/state-target"
ln -s "$test_tmp/state-target" "$state_dir"
if run_helper stop 2>/dev/null; then
  fail "symlink inhibitor state directory is rejected"
fi
rm -f "$state_dir"
mkdir -m 755 "$state_dir"
if run_helper stop 2>/dev/null; then
  fail "permissive inhibitor state directory is rejected"
fi
rm -rf "$state_dir"
pass "unsafe inhibitor state directories are rejected"

prepare_state_dir
printf 'not a record\n' >"$state_dir/inhibit-pid"
chmod 600 "$state_dir/inhibit-pid"
if run_helper stop 2>/dev/null; then
  fail "malformed inhibitor state is rejected"
fi

token=11111111111111111111111111111111
start_identity_process "$token"
prepare_state_dir
printf '1 %s %s %s %s\nextra\n' "$identity_pid" "$identity_start" "$identity_owner" "$token" >"$state_dir/inhibit-pid"
chmod 600 "$state_dir/inhibit-pid"
if run_helper stop 2>/dev/null; then
  fail "multiline inhibitor state is rejected"
fi
kill -0 "$identity_pid" 2>/dev/null || fail "multiline state cannot signal its target"

prepare_state_dir
write_inhibit_state "1 $identity_pid $((identity_start + 1)) $identity_owner $token"
run_helper stop
kill -0 "$identity_pid" 2>/dev/null || fail "reused PID state cannot signal its target"

prepare_state_dir
write_inhibit_state "1 $identity_pid $identity_start $identity_owner 22222222222222222222222222222222"
run_helper stop
kill -0 "$identity_pid" 2>/dev/null || fail "wrong process identity cannot signal its target"
kill "$identity_pid"
wait_dead "$identity_pid" || true
pass "malformed, multiline, reused-PID, and wrong-identity records are harmless"

retry_flag="$test_tmp/allow-termination"
token=44444444444444444444444444444444
/usr/bin/bash -c '
  trap "" TERM
  while [[ ! -e $1 ]]; do sleep 0.05; done
  trap "exit 0" TERM
  while :; do sleep 0.05; done
' omarchy-retry "$retry_flag" "--why=Omarchy update in progress [$token]" &
retry_pid=$!
test_processes+=("$retry_pid")
retry_start=$(awk '{ print $22 }' "/proc/$retry_pid/stat")
retry_owner=$(stat -Lc '%u' "/proc/$retry_pid")
prepare_state_dir
write_inhibit_state "1 $retry_pid $retry_start $retry_owner $token"
if run_helper stop 2>/dev/null; then
  fail "failed termination reports success"
fi
[[ -s $state_dir/inhibit-pid ]] || fail "failed termination retains authenticated retry state"
touch "$retry_flag"
sleep 0.1
run_helper stop
wait_dead "$retry_pid" || fail "retained inhibitor state permits a successful retry"
pass "failed termination retains its authenticated retry handle"

for unsafe_kind in symlink permissive hardlink; do
  token=33333333333333333333333333333333
  start_identity_process "$token"
  prepare_state_dir
  record="1 $identity_pid $identity_start $identity_owner $token"
  case "$unsafe_kind" in
    symlink)
      printf '%s\n' "$record" >"$test_tmp/state-victim"
      chmod 600 "$test_tmp/state-victim"
      ln -s "$test_tmp/state-victim" "$state_dir/inhibit-pid"
      ;;
    permissive)
      write_inhibit_state "$record"
      chmod 644 "$state_dir/inhibit-pid"
      ;;
    hardlink)
      write_inhibit_state "$record"
      ln "$state_dir/inhibit-pid" "$state_hardlink"
      ;;
  esac
  if run_helper stop 2>/dev/null; then
    fail "$unsafe_kind inhibitor state is rejected"
  fi
  kill -0 "$identity_pid" 2>/dev/null || fail "$unsafe_kind state cannot signal its target"
  kill "$identity_pid"
  wait_dead "$identity_pid" || true
  rm -f "$test_tmp/state-victim" "$state_hardlink"
done
pass "symlink, permissive, and multiply-linked records are harmless"

: >"$inhibitor_log"
run_helper start
first_pid=$(tail -n 1 "$inhibitor_log")
run_helper start
second_pid=$(tail -n 1 "$inhibitor_log")
[[ $first_pid != "$second_pid" ]] || fail "repeated start replaces the inhibitor"
wait_dead "$first_pid" || fail "repeated start stops the prior inhibitor"
run_helper stop
run_helper stop
wait_dead "$second_pid" || fail "repeated stop remains idempotent"
pass "repeated start and stop preserve one inhibitor"

: >"$inhibitor_log"
concurrent_jobs=()
for _ in {1..4}; do
  (run_helper start; run_helper stop) &
  concurrent_jobs+=("$!")
done
for job in "${concurrent_jobs[@]}"; do
  wait "$job" || fail "concurrent start and stop are serialized"
done
run_helper stop
while read -r pid; do
  [[ -n $pid ]] || continue
  wait_dead "$pid" || fail "concurrent operation leaves no inhibitor behind"
done <"$inhibitor_log"
pass "concurrent state operations are serialized"

if SYSTEMD_FAIL=1 run_helper start; then
  [[ ! -e $state_dir/inhibit-pid ]] || fail "failed inhibitor launch publishes no PID state"
else
  fail "failed systemd-inhibit launch still allows the idle fallback"
fi
run_helper stop
pass "failed inhibitor launch leaves no stale process state"

: >"$inhibitor_log"
rollback_victim="$test_tmp/rollback-victim"
: >"$rollback_victim"
if CREATE_BAD_IDLE="$rollback_victim" run_helper start 2>/dev/null; then
  fail "unsafe idle publication reports success"
fi
rollback_pid=$(tail -n 1 "$inhibitor_log")
wait_dead "$rollback_pid" || fail "post-publication failure rolls the inhibitor back"
[[ ! -e $state_dir/inhibit-pid ]] || fail "rollback removes published inhibitor state"
pass "state publication failures roll back a launched inhibitor"

namespace_args=()
namespace_probe_error="$test_tmp/namespace-probe.err"
if (( EUID == 0 )); then
  namespace_args=(
    unshare --user --mount --fork
    --map-users=0:0:1 --map-users=1000:1000:2
    --map-groups=0:0:1 --map-groups=1000:1000:2
    --setuid=0 --setgid=0
  )
else
  subordinate_uid=$(awk -F: -v user="$(id -un)" '$1 == user { print $2; exit }' /etc/subuid 2>/dev/null || true)
  subordinate_gid=$(awk -F: -v user="$(id -un)" '$1 == user { print $2; exit }' /etc/subgid 2>/dev/null || true)
  if [[ $subordinate_uid =~ ^[0-9]+$ && $subordinate_gid =~ ^[0-9]+$ ]]; then
    namespace_args=(
      unshare --user --mount --fork
      "--map-users=0:$(id -u):1" "--map-users=1000:$subordinate_uid:2"
      "--map-groups=0:$(id -g):1" "--map-groups=1000:$subordinate_gid:2"
      --setuid=0 --setgid=0
    )
  fi
fi

namespace_capable=0
if (( ${#namespace_args[@]} > 0 )) &&
  "${namespace_args[@]}" /usr/bin/bash -c '
    mount -t tmpfs -o mode=1777 tmpfs /tmp
    setpriv --reuid=1000 --regid=1000 --clear-groups true
    setpriv --reuid=1001 --regid=1001 --clear-groups true
  ' 2>"$namespace_probe_error"; then
  namespace_capable=1
fi

if (( namespace_capable == 0 )); then
  pass "two-UID namespace capability unavailable; skipping cross-UID fallback probe"
else
  if ! "${namespace_args[@]}" /usr/bin/bash -s 9<"$ROOT/bin/omarchy-update-stay-awake" <<'SH'
set -euo pipefail
mount -t tmpfs -o mode=1777 tmpfs /tmp
mkdir -m 700 /tmp/victim-home
chown 1000:1000 /tmp/victim-home

setpriv --reuid=1000 --regid=1000 --clear-groups sleep 30 &
victim_pid=$!
victim_start=$(awk '{ print $22 }' "/proc/$victim_pid/stat")

setpriv --reuid=1001 --regid=1001 --clear-groups /usr/bin/bash -c '
  mkdir -m 700 /tmp/omarchy-1000
  mkdir -m 700 /tmp/omarchy-1000/omarchy-update-stay-awake
  printf "%s %s\n" "$1" "$2" >/tmp/omarchy-1000/omarchy-update-stay-awake/inhibit-pid
  chmod 600 /tmp/omarchy-1000/omarchy-update-stay-awake/inhibit-pid
' attacker "$victim_pid" "$victim_start"

if setpriv --reuid=1000 --regid=1000 --clear-groups env -u XDG_RUNTIME_DIR \
  HOME=/tmp/victim-home PATH=/usr/bin:/bin /usr/bin/bash /proc/self/fd/9 stop 2>/dev/null; then
  echo "foreign fallback state was accepted" >&2
  exit 1
fi
kill -0 "$victim_pid"

rm -rf /tmp/omarchy-1000
mkdir -m 755 /tmp/probe-bin
printf '#!/bin/bash\nexit 1\n' >/tmp/probe-bin/omarchy-cmd-present
printf '#!/bin/bash\ncase "$1" in stay-awake) mkdir -p "$HOME/.local/state/omarchy/indicators"; touch "$HOME/.local/state/omarchy/indicators/stay-awake";; allow-idle) rm -f "$HOME/.local/state/omarchy/indicators/stay-awake";; esac\n' >/tmp/probe-bin/omarchy-toggle-idle
chmod 755 /tmp/probe-bin/*
setpriv --reuid=1000 --regid=1000 --clear-groups env -u XDG_RUNTIME_DIR \
  HOME=/tmp/victim-home PATH=/tmp/probe-bin:/usr/bin:/bin /usr/bin/bash /proc/self/fd/9 start
[[ $(stat -Lc '%u %a' /tmp/omarchy-1000) == "1000 700" ]]
setpriv --reuid=1000 --regid=1000 --clear-groups env -u XDG_RUNTIME_DIR \
  HOME=/tmp/victim-home PATH=/tmp/probe-bin:/usr/bin:/bin /usr/bin/bash /proc/self/fd/9 stop

mkdir -m 700 /tmp/omarchy-1000/omarchy-update-stay-awake
chown 1000:1000 /tmp/omarchy-1000/omarchy-update-stay-awake
printf '1 %s %s 1000 %032d\n' "$victim_pid" "$victim_start" 0 \
  >/tmp/omarchy-1000/omarchy-update-stay-awake/inhibit-pid
chown 1001:1001 /tmp/omarchy-1000/omarchy-update-stay-awake/inhibit-pid
chmod 600 /tmp/omarchy-1000/omarchy-update-stay-awake/inhibit-pid
if setpriv --reuid=1000 --regid=1000 --clear-groups env -u XDG_RUNTIME_DIR \
  HOME=/tmp/victim-home PATH=/tmp/probe-bin:/usr/bin:/bin /usr/bin/bash /proc/self/fd/9 stop 2>/dev/null; then
  echo "foreign state file was accepted" >&2
  exit 1
fi
kill -0 "$victim_pid"
rm -rf /tmp/omarchy-1000/omarchy-update-stay-awake

mkdir -m 700 /tmp/root-home
env -u XDG_RUNTIME_DIR HOME=/tmp/root-home PATH=/tmp/probe-bin:/usr/bin:/bin \
  /usr/bin/bash /proc/self/fd/9 start
[[ $(stat -Lc '%u %a' /tmp/omarchy-0) == "0 700" ]]
env -u XDG_RUNTIME_DIR HOME=/tmp/root-home PATH=/tmp/probe-bin:/usr/bin:/bin \
  /usr/bin/bash /proc/self/fd/9 stop

kill "$victim_pid"
wait "$victim_pid" 2>/dev/null || true
SH
  then
    fail "two-UID fallback probe failed after its capability check" "$(<"$namespace_probe_error")"
  fi
  pass "foreign UID fallback state cannot kill a victim and safe fallback works"
fi
