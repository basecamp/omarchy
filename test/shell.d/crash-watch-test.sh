#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin"
NOTIFY_LOG="$TMPDIR/notify-log"
: >"$NOTIFY_LOG"

uid=$(id -u)
boot=deadbeefdeadbeefdeadbeefdeadbeef

# inotifywait: emit the scripted core filenames from $WATCH_ITEMS, then exit
# like a watch that dropped. The watcher must process every name it sees.
cat >"$TMPDIR/bin/inotifywait" <<'SH'
#!/bin/bash
printf '%s\n' $WATCH_ITEMS
SH

# coredumpctl: the watcher calls `info COREDUMP_PID=<pid> _BOOT_ID=<boot>`;
# reply with the fields the awk extraction reads. Unknown pids get no entry,
# exercising the tolerated-lookup-failure path.
cat >"$TMPDIR/bin/coredumpctl" <<'SH'
#!/bin/bash
case "$2" in
  COREDUMP_PID=1001) printf '%s\n' \
      '           PID: 1001 (foo-bar)' \
      '        Signal: 11 (SEGV) si_code: SI_KERNEL' \
      '    Executable: /usr/bin/foo-bar-real' ;;
  COREDUMP_PID=1002) printf '%s\n' \
      '           PID: 1002 (other)' \
      '        Signal: 6 (ABRT)' \
      '    Executable: /usr/bin/other-real' ;;
  *) : ;;
esac
SH

cat >"$TMPDIR/bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$NOTIFY_LOG"
SH

cat >"$TMPDIR/bin/omarchy-notification-wait" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$TMPDIR/bin/omarchy-default-agent" <<'SH'
#!/bin/bash
printf '%s\n' default-agent
SH

chmod +x "$TMPDIR/bin"/*

run_watch() {
  local items=$1
  shift
  (
    export PATH="$TMPDIR/bin:$ROOT/bin:$PATH"
    export WATCH_ITEMS="$items" NOTIFY_LOG="$NOTIFY_LOG"
    for kv in "$@"; do export "$kv"; done
    "$ROOT/bin/omarchy-crash-watch"
  )
}

notify_count() {
  wc -l <"$NOTIFY_LOG"
}

core_file() { # comm uid pid
  printf 'core.%s.%s.%s.%s.1786000000000000.zst' "$1" "$2" "$boot" "$3"
}

: >"$NOTIFY_LOG"
run_watch "$(core_file foo-bar "$uid" 1001) $(core_file other "$uid" 1002)"
[[ $(notify_count) -eq 2 ]] ||
  fail "one toast per crash" "got: $(notify_count) toasts"
grep -Fq "Process crashed: foo-bar-real" "$NOTIFY_LOG" ||
  fail "toast uses the executable basename, not the 15-char comm"
grep -Fq "Process crashed: other-real" "$NOTIFY_LOG" ||
  fail "toast for the second crash"
grep -Fq "omarchy-agent-crash 1001 foo-bar-real /usr/bin/foo-bar-real SEGV" "$NOTIFY_LOG" ||
  fail "diagnosis command carries pid, name, executable, and signal"
grep -Fq "omarchy-agent-crash 1002 other-real /usr/bin/other-real ABRT" "$NOTIFY_LOG" ||
  fail "diagnosis command for the second crash"
! grep -Fq "Process crashed: foo-bar " "$NOTIFY_LOG" ||
  fail "truncated comm never reaches the toast when the executable is known"
pass "watcher announces crashes with name, executable, and signal"

: >"$NOTIFY_LOG"
run_watch \
  "$(core_file alien 424242 3001) $(core_file omarchy-agent-foo "$uid" 1002) $(core_file other "$uid" 1002)" \
  OMARCHY_CRASH_DEDUPE_SECONDS=0
[[ $(notify_count) -eq 1 ]] ||
  fail "foreign-uid and omarchy-own crashes are skipped" "got: $(notify_count) toasts"
grep -Fq "Process crashed: other-real" "$NOTIFY_LOG" ||
  fail "the remaining crash is still announced"
pass "watcher skips other users' and its own crashes"

: >"$NOTIFY_LOG"
run_watch "$(core_file foo-bar "$uid" 1001) $(core_file other "$uid" 1002)" \
  OMARCHY_CRASH_IGNORE='foo'
[[ $(notify_count) -eq 1 ]] ||
  fail "ignored patterns are not announced" "got: $(notify_count) toasts"
grep -Fq "Process crashed: other-real" "$NOTIFY_LOG" ||
  fail "non-ignored crashes are still announced"
pass "watcher honors the ignore pattern"

: >"$NOTIFY_LOG"
run_watch "$(core_file foo-bar "$uid" 1001) $(core_file foo-bar "$uid" 1001)" \
  OMARCHY_CRASH_DEDUPE_SECONDS=3600
[[ $(notify_count) -eq 1 ]] ||
  fail "duplicate core files within the dedupe window are announced once" "got: $(notify_count) toasts"
pass "watcher dedupes crash loops per window"

: >"$NOTIFY_LOG"
run_watch "$(core_file foo-bar "$uid" 1001) $(core_file foo-bar "$uid" 1001)" \
  OMARCHY_CRASH_DEDUPE_SECONDS=0
[[ $(notify_count) -eq 2 ]] ||
  fail "a zero dedupe window announces every core file" "got: $(notify_count) toasts"
pass "watcher announces again outside the dedupe window"

: >"$NOTIFY_LOG"
run_watch "$(core_file barecomm "$uid" 3001)"
[[ $(notify_count) -eq 1 ]] ||
  fail "crash without a coredumpctl entry is still announced"
grep -Fq "Process crashed: barecomm" "$NOTIFY_LOG" ||
  fail "falls back to the truncated comm from the filename"
grep -Fq "omarchy-agent-crash 3001 barecomm unknown unknown" "$NOTIFY_LOG" ||
  fail "falls back to unknown executable and signal"
pass "watcher tolerates a failed coredumpctl lookup"
