#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "$0")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1788009111.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin" "$test_tmp/var/lib/omarchy/migrations"

# Every privileged step is stubbed: a real run here would take printer
# discovery off the developer's own machine.
cat >"$mock_bin/omarchy-pkg-present" <<'SH'
#!/bin/bash
[[ " $BROWSED_INSTALLED " == *" $1 "* ]]
SH

cat >"$mock_bin/omarchy-pkg-drop" <<'SH'
#!/bin/bash
printf 'omarchy-pkg-drop\t%s\n' "$*" >>"$BROWSED_LOG"
[[ -z $BROWSED_DROP_FAILS ]]
SH

cat >"$mock_bin/pacman" <<'SH'
#!/bin/bash
printf 'pacman\t%s\n' "$*" >>"$BROWSED_LOG"
if [[ $* == *--print* ]]; then
  [[ -z $BROWSED_REMOVAL_BLOCKED ]]
fi
SH

cat >"$mock_bin/systemctl" <<'SH'
#!/bin/bash
printf 'systemctl\t%s\n' "$*" >>"$BROWSED_LOG"
unit=$3
case $1 in
  is-enabled) [[ " $BROWSED_ENABLED " == *" $unit "* ]] ;;
  is-active) [[ " $BROWSED_ACTIVE " == *" $unit "* ]] ;;
  *) : ;;
esac
SH

cat >"$mock_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo\t%s\n' "$*" >>"$BROWSED_LOG"
exec "$@"
SH

cat >"$mock_bin/install" <<'SH'
#!/bin/bash
printf 'install\t%s\n' "$*" >>"$BROWSED_LOG"
exec /usr/bin/install "$@"
SH

# lpstat reports only package-generated queues on the implicitclass backend.
# Manual ipp:// and usb:// printers must survive.
cat >"$mock_bin/lpstat" <<'SH'
#!/bin/bash
printf 'lpstat\t%s\n' "$*" >>"$BROWSED_LOG"
case $1 in
  -v)
    if [[ -n $BROWSED_LPSTAT_FAILS ]]; then
      echo "lpstat: Scheduler is not responding." >&2
      exit 1
    elif [[ -z $BROWSED_QUEUES ]]; then
      echo "lpstat: No destinations added." >&2
      exit 1
    elif [[ $LC_ALL == "C" ]]; then
      printf '%s\n' "$BROWSED_QUEUES"
    else
      printf '%s\n' "$BROWSED_QUEUES" | sed 's|^device for |Gerät für |'
    fi
    ;;
  -p)
    [[ " $BROWSED_GONE_QUEUES " != *" $2 "* ]]
    ;;
  -o)
    if [[ -n $BROWSED_LPSTAT_O_FAILS ]]; then
      echo "lpstat: Scheduler is not responding." >&2
      exit 1
    fi
    if [[ " $BROWSED_BUSY_QUEUES " == *" $2 "* ]]; then
      printf '%s-7 alice 1024\n' "$2"
    fi
    ;;
esac
SH

cat >"$mock_bin/lpadmin" <<'SH'
#!/bin/bash
printf 'lpadmin\t%s\n' "$*" >>"$BROWSED_LOG"
if [[ -n $BROWSED_LPADMIN_FAILS ]]; then
  echo "lpadmin: Printer does not exist." >&2
  exit 1
fi
SH

cat >"$mock_bin/cupsreject" <<'SH'
#!/bin/bash
printf 'cupsreject\t%s\n' "$*" >>"$BROWSED_LOG"
if [[ -n $BROWSED_REJECT_FAILS ]]; then
  echo "cupsreject: Unable to reject jobs." >&2
  exit 1
fi
SH

chmod +x "$mock_bin"/*

log="$test_tmp/actions.log"
output="$test_tmp/migration.out"
errors="$test_tmp/migration.err"
status=0

start_case() {
  installed="cups-browsed"
  enabled="cups-browsed.service"
  active="cups-browsed.service cups.service"
  blocked=""
  drop_fails=""
  queues=""
  busy=""
  lpstat_fails=""
  lpstat_o_fails=""
  lpadmin_fails=""
  reject_fails=""
  gone_queues=""
  use_marker="$test_tmp/var/lib/omarchy/migrations/$1"
  rm -f "$use_marker"
}

run_migration() {
  : >"$log"
  : >"$output"
  : >"$errors"

  if env -u LC_ALL -u LANGUAGE \
    BROWSED_LOG="$log" \
    BROWSED_INSTALLED="$installed" \
    BROWSED_ENABLED="$enabled" \
    BROWSED_ACTIVE="$active" \
    BROWSED_REMOVAL_BLOCKED="$blocked" \
    BROWSED_DROP_FAILS="$drop_fails" \
    BROWSED_QUEUES="$queues" \
    BROWSED_BUSY_QUEUES="$busy" \
    BROWSED_LPSTAT_FAILS="$lpstat_fails" \
    BROWSED_LPSTAT_O_FAILS="$lpstat_o_fails" \
    BROWSED_LPADMIN_FAILS="$lpadmin_fails" \
    BROWSED_REJECT_FAILS="$reject_fails" \
    BROWSED_GONE_QUEUES="$gone_queues" \
    PATH="$mock_bin:$PATH" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_CUPS_BROWSED_REMOVAL_MARKER="$use_marker" \
    bash -euo pipefail "$migration" >"$output" 2>"$errors"; then
    status=0
  else
    status=$?
  fi
}

assert_description_only() {
  [[ $(<"$output") == "Temporarily remove automatic printer discovery" ]] ||
    fail "the migration prints only its description" "$(cat "$output")"
}

assert_quiet_success() {
  (( status == 0 )) || fail "the migration succeeds" "$(cat "$errors")"
  assert_description_only
  [[ ! -s $errors ]] || fail "a successful migration is quiet" "$(cat "$errors")"
}

# ------------------------------------------------ a machine that has printers

start_case printers
queues=$'device for Office: implicitclass://Office/\ndevice for Front_Desk: implicitclass://Front_Desk/\ndevice for all: implicitclass://all/\ndevice for Desk: ipp://192.168.1.9/ipp/print\ndevice for Attic: usb://HP/LaserJet%20P1102'
run_migration
assert_quiet_success

grep -qxF $'pacman\t-Rs --print cups-browsed' "$log" ||
  fail "the migration preflights the package removal" "$(cat "$log")"
grep -qxF $'sudo\tsystemctl disable --now cups-browsed.service' "$log" ||
  fail "the migration disables and stops discovery" "$(cat "$log")"
for queue in Office Front_Desk all; do
  grep -qxF "sudo	lpadmin -x $queue" "$log" ||
    fail "the migration removes generated queue $queue" "$(cat "$log")"
done
grep -q 'lpadmin -x Desk' "$log" &&
  fail "the migration leaves a manually-added IPP printer alone" "$(cat "$log")"
grep -q 'lpadmin -x Attic' "$log" &&
  fail "the migration leaves a manually-added USB printer alone" "$(cat "$log")"
grep -qxF $'omarchy-pkg-drop\tcups-browsed' "$log" ||
  fail "the migration uses the standard package removal helper" "$(cat "$log")"
[[ -f $use_marker ]] || fail "the migration records machine-wide completion"

disable_line=$(grep -n 'disable --now' "$log" | head -1 | cut -d: -f1)
cleanup_line=$(grep -n 'lpadmin -x' "$log" | tail -1 | cut -d: -f1)
removal_line=$(grep -n 'omarchy-pkg-drop' "$log" | head -1 | cut -d: -f1)
(( disable_line < cleanup_line && cleanup_line < removal_line )) ||
  fail "the service and queues are handled before package removal" "$(cat "$log")"
pass "generated queues are removed, manual printers survive, and normal output is quiet"

# ------------------------------------ a second user, after a deliberate reinstall

run_migration
assert_quiet_success
[[ ! -s $log ]] || fail "a completed machine-wide removal is left alone" "$(cat "$log")"
pass "a second user does not undo a deliberate reinstall"

# ----------------------------------------- a machine that never had discovery

start_case no-package
installed=""
run_migration
assert_quiet_success
[[ ! -s $log ]] || fail "a machine without discovery is left alone" "$(cat "$log")"
[[ ! -e $use_marker ]] || fail "a machine without discovery gets no marker"
pass "a machine without cups-browsed does no privileged work"

# --------------------------------------------- a machine that has no printers

start_case no-printers
run_migration
assert_quiet_success
grep -qxF $'omarchy-pkg-drop\tcups-browsed' "$log" ||
  fail "no printers does not prevent package removal" "$(cat "$log")"
grep -qE 'cupsreject|lpadmin' "$log" &&
  fail "no printers requires no queue administration" "$(cat "$log")"
[[ -f $use_marker ]] || fail "the no-printer migration records completion"
pass "CUPS reporting no destinations is a successful empty migration"

# ------------------------------------------------- a blocked package removal

start_case blocked
blocked="1"
run_migration
(( status != 0 )) || fail "a blocked package removal remains pending"
assert_description_only
grep -q 'disable --now' "$log" &&
  fail "a blocked removal does not stop discovery" "$(cat "$log")"
grep -q 'omarchy-pkg-drop' "$log" &&
  fail "a blocked removal does not invoke package removal" "$(cat "$log")"
[[ ! -e $use_marker ]] || fail "a blocked removal gets no marker"
pass "a package dependency prevents any partial migration"

# --------------------------------------------------- a queue that has jobs

start_case busy
queues=$'device for Office: implicitclass://Office/\ndevice for Spare: implicitclass://Spare/'
busy="Office"
run_migration
assert_quiet_success
grep -q 'lpadmin -x Office' "$log" &&
  fail "a queue with jobs is not deleted" "$(cat "$log")"
grep -qxF $'sudo\tlpadmin -x Spare' "$log" ||
  fail "an idle generated queue is deleted" "$(cat "$log")"
grep -qxF $'omarchy-pkg-drop\tcups-browsed' "$log" ||
  fail "a busy queue does not retain the discovery package" "$(cat "$log")"

reject_line=$(grep -n 'cupsreject.*Spare' "$log" | head -1 | cut -d: -f1)
probe_line=$(grep -n $'^lpstat\t-o Spare' "$log" | head -1 | cut -d: -f1)
delete_line=$(grep -n 'lpadmin -x Spare' "$log" | head -1 | cut -d: -f1)
(( reject_line < probe_line && probe_line < delete_line )) ||
  fail "a queue is closed before it is checked and deleted" "$(cat "$log")"
pass "busy queues survive while idle discovery queues are removed"

# ------------------------------------------------- a job query that fails

start_case job-query-fails
queues=$'device for Office: implicitclass://Office/'
lpstat_o_fails="1"
run_migration
(( status != 0 )) || fail "a failed job query keeps the migration pending"
assert_description_only
grep -q 'lpadmin -x' "$log" &&
  fail "a queue with unknown job state is not deleted" "$(cat "$log")"
grep -q 'omarchy-pkg-drop' "$log" &&
  fail "a failed job query retains the package" "$(cat "$log")"
[[ ! -e $use_marker ]] || fail "a failed job query gets no marker"
pass "a failed job query is retryable instead of falsely completing"

# ------------------------------------------------------ CUPS out of reach

start_case no-cups
queues=$'device for Office: implicitclass://Office/'
lpstat_fails="1"
run_migration
(( status != 0 )) || fail "an unavailable CUPS server keeps the migration pending"
assert_description_only
grep -qxF "lpstat: Scheduler is not responding." "$errors" ||
  fail "the underlying CUPS failure is preserved" "$(cat "$errors")"
grep -q 'omarchy-pkg-drop' "$log" &&
  fail "an unavailable CUPS server retains the package" "$(cat "$log")"
[[ ! -e $use_marker ]] || fail "an unavailable CUPS server gets no marker"
pass "an actual CUPS failure remains pending without custom telemetry"

# ------------------------------------------------ a queue that will not go

start_case stuck-queue
queues=$'device for Office: implicitclass://Office/'
lpadmin_fails="1"
run_migration
(( status != 0 )) || fail "a failed queue deletion keeps the migration pending"
grep -q 'omarchy-pkg-drop' "$log" &&
  fail "a persistent generated queue retains the backend" "$(cat "$log")"
[[ ! -e $use_marker ]] || fail "a failed queue deletion gets no marker"
pass "a persistent generated queue prevents partial completion"

# --------------------------------------------- a queue removed concurrently

start_case vanished-queue
queues=$'device for Office: implicitclass://Office/'
lpadmin_fails="1"
gone_queues="Office"
run_migration
assert_quiet_success
grep -qxF $'omarchy-pkg-drop\tcups-browsed' "$log" ||
  fail "a concurrently removed queue does not block package removal" "$(cat "$log")"
pass "a queue removed concurrently counts as removed"

# ------------------------------------------- a queue that cannot be closed

start_case open-queue
queues=$'device for Office: implicitclass://Office/'
reject_fails="1"
run_migration
(( status != 0 )) || fail "a queue that cannot be closed keeps the migration pending"
grep -q 'lpadmin -x' "$log" &&
  fail "a queue still accepting jobs is not deleted" "$(cat "$log")"
grep -q 'omarchy-pkg-drop' "$log" &&
  fail "a queue still accepting jobs retains the backend" "$(cat "$log")"
[[ ! -e $use_marker ]] || fail "a queue still accepting jobs gets no marker"
pass "a queue that cannot be closed is retried later"

# -------------------------------------------------- a masked but running daemon

start_case masked
enabled=""
active="cups-browsed.service"
run_migration
assert_quiet_success
grep -qxF $'sudo\tsystemctl stop cups-browsed.service' "$log" ||
  fail "a masked running daemon is stopped" "$(cat "$log")"
grep -q 'disable --now' "$log" &&
  fail "a masked unit is not disabled" "$(cat "$log")"
pass "a masked running daemon is stopped without noisy output"

# ------------------------------------------------ a package removal that fails

start_case drop-fails
drop_fails="1"
run_migration
(( status != 0 )) || fail "a failed package removal keeps the migration pending"
assert_description_only
[[ ! -e $use_marker ]] || fail "a failed package removal gets no marker"
pass "a package removal failure cannot be recorded as complete"
