#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
reader_state_dir="$test_tmp/readers"
signal_log="$test_tmp/pkill"
inspection_state="$test_tmp/inspection"
mkdir -p "$mock_bin"

export PATH="$mock_bin:$PATH"
export NEWSBOAT_READER_STATE_DIR="$reader_state_dir"
export NEWSBOAT_CLOSE_TEST_SIGNAL_LOG="$signal_log"
export NEWSBOAT_CLOSE_TEST_INSPECTION_STATE="$inspection_state"

write_mock() {
  local name=$1
  shift
  printf '#!/bin/bash\n%s\n' "$*" >"$mock_bin/$name"
  chmod +x "$mock_bin/$name"
}

write_reader() {
  local wrapper_pid=$1 cache=$2
  mkdir -p "$reader_state_dir"
  jq -cn --argjson pid "$wrapper_pid" --arg cache "$cache" \
    '{version: 1, pid: $pid, cache: $cache}' >"$reader_state_dir/reader.$wrapper_pid"
}

reset_probe() {
  rm -f "$signal_log"
  rm -rf "$inspection_state"
  mkdir -p "$inspection_state"
}

write_mock ps '
case "$*" in
  *" uid="*) printf "%s\n" "$UID" ;;
  *" args="*)
    if [[ ${NEWSBOAT_CLOSE_TEST_MODE:-} == reused ]]; then
      printf "/bin/bash unrelated-command\n"
    else
      printf "/bin/bash /home/test/omarchy-newsboat-read\n"
    fi
    ;;
  *) exit 2 ;;
esac
'

write_mock pgrep '
wrapper=""
while (($#)); do
  if [[ $1 == "-P" ]]; then wrapper=$2; shift 2; else shift; fi
done
mkdir -p "$NEWSBOAT_CLOSE_TEST_INSPECTION_STATE"
counter="$NEWSBOAT_CLOSE_TEST_INSPECTION_STATE/$wrapper"
count=0
[[ ! -f $counter ]] || count=$(<"$counter")
printf "%s\n" "$((count + 1))" >"$counter"
case ${NEWSBOAT_CLOSE_TEST_MODE:-none} in
  closes) (( wrapper == 111 && count == 0 )) && { echo 501; exit 0; } || exit 1 ;;
  stuck) (( wrapper == 111 )) && { echo 501; exit 0; } || exit 1 ;;
  error) exit 2 ;;
  reused|none) exit 1 ;;
  *) exit 2 ;;
esac
'

write_mock pkill '
printf "%s\n" "$*" >>"$NEWSBOAT_CLOSE_TEST_SIGNAL_LOG"
[[ ${NEWSBOAT_CLOSE_TEST_SIGNAL_FAIL:-0} != 1 ]] || exit 2
'
write_mock sleep 'exit 0'

if "$ROOT/bin/omarchy-newsboat-close" >/dev/null 2>&1; then
  fail "Newsboat close accepts a missing cache target"
fi
pass "Newsboat close requires an exact cache target"

export NEWSBOAT_CLOSE_TEST_MODE=none
"$ROOT/bin/omarchy-newsboat-close" /tmp/cache-a
[[ ! -e $signal_log ]] || fail "closing without a registered Feeds reader sends a signal"
pass "Newsboat close is a no-op without a registered Feeds reader"

write_reader 222 /tmp/cache-b
reset_probe
"$ROOT/bin/omarchy-newsboat-close" /tmp/cache-a
[[ ! -e $signal_log ]] || fail "closing one cache signals a different registered reader"
pass "Newsboat close leaves unrelated registered caches alone"

write_reader 111 /tmp/cache-a
reset_probe
export NEWSBOAT_CLOSE_TEST_MODE=closes
"$ROOT/bin/omarchy-newsboat-close" /tmp/cache-a
grep -Fxq -- "-TERM -P 111 -x newsboat" "$signal_log" || fail "Newsboat close does not target the registered Feeds wrapper"
if grep -Fq -- "-P 222" "$signal_log"; then
  fail "Newsboat close signals an unrelated registered reader"
fi
pass "Newsboat close targets only the registered reader for its cache"

reset_probe
export NEWSBOAT_CLOSE_TEST_MODE=stuck NEWSBOAT_CLOSE_ATTEMPTS=2
if "$ROOT/bin/omarchy-newsboat-close" /tmp/cache-a >/dev/null 2>&1; then
  fail "Newsboat close reports success while its targeted reader remains"
fi
pass "Newsboat close fails safely when its targeted reader remains"

reset_probe
export NEWSBOAT_CLOSE_TEST_MODE=error NEWSBOAT_CLOSE_ATTEMPTS=50
if "$ROOT/bin/omarchy-newsboat-close" /tmp/cache-a >/dev/null 2>&1; then
  fail "Newsboat close ignores targeted process inspection errors"
fi
[[ ! -e $signal_log ]] || fail "an inspection failure still signals a reader"
pass "Newsboat close fails before signaling when inspection fails"

reset_probe
export NEWSBOAT_CLOSE_TEST_MODE=reused
"$ROOT/bin/omarchy-newsboat-close" /tmp/cache-a
[[ ! -e $reader_state_dir/reader.111 ]] || fail "Newsboat close retains a registration whose wrapper PID was reused"
[[ ! -e $signal_log ]] || fail "Newsboat close signals a child of a reused wrapper PID"
pass "Newsboat close discards stale registrations without signaling"

write_reader 111 /tmp/cache-a
reset_probe
export NEWSBOAT_CLOSE_TEST_MODE=closes NEWSBOAT_CLOSE_TEST_SIGNAL_FAIL=1
if "$ROOT/bin/omarchy-newsboat-close" /tmp/cache-a >/dev/null 2>&1; then
  fail "Newsboat close ignores a targeted signal failure"
fi
unset NEWSBOAT_CLOSE_TEST_SIGNAL_FAIL
pass "Newsboat close fails safely when the targeted signal fails"

printf '%s\n' '{"version":1,"pid":"not-a-pid","cache":"/tmp/cache-a"}' >"$reader_state_dir/reader.invalid"
reset_probe
if "$ROOT/bin/omarchy-newsboat-close" /tmp/cache-a >/dev/null 2>&1; then
  fail "Newsboat close trusts malformed reader registration"
fi
[[ ! -e $signal_log ]] || fail "malformed reader state still signals a process"
pass "Newsboat close fails closed on malformed reader state"

rm -rf "$reader_state_dir"
symlinked_state_target="$test_tmp/symlinked-readers"
mkdir -p "$symlinked_state_target"
/bin/ln -s "$symlinked_state_target" "$reader_state_dir"
reset_probe
if "$ROOT/bin/omarchy-newsboat-close" /tmp/cache-a >/dev/null 2>&1; then
  fail "Newsboat close trusts a symlinked reader-state directory"
fi
[[ ! -e $signal_log ]] || fail "symlinked reader state can trigger a process signal"
rm -f "$reader_state_dir"
pass "Newsboat close rejects symlinked reader state"

mkdir -p "$reader_state_dir"
reader_target="$test_tmp/reader-target"
jq -cn '{version: 1, pid: 111, cache: "/tmp/cache-a"}' >"$reader_target"
/bin/ln -s "$reader_target" "$reader_state_dir/reader.111"
reset_probe
if "$ROOT/bin/omarchy-newsboat-close" /tmp/cache-a >/dev/null 2>&1; then
  fail "Newsboat close trusts a symlinked reader registration"
fi
[[ ! -e $signal_log ]] || fail "symlinked reader registration can trigger a process signal"
pass "Newsboat close rejects symlinked reader registrations"
