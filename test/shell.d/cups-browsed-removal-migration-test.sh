#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1788009111.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin" "$test_tmp/var/lib/omarchy/migrations"

# Every privileged step is stubbed: a real run here would take printer discovery
# off the developer's own machine.
cat >"$mock_bin/omarchy-pkg-present" <<'SH'
#!/bin/bash
[[ " $BROWSED_INSTALLED " == *" $1 "* ]]
SH

# pacman answers the removal preflight from the state each case sets up, and
# logs the removal itself so the flags it is called with are visible.
cat >"$mock_bin/pacman" <<'SH'
#!/bin/bash
printf 'pacman\t%s\n' "$*" >>"$BROWSED_LOG"
[[ $* == *--print* ]] || exit 0
[[ -z $BROWSED_REMOVAL_BLOCKED ]]
SH

cat >"$mock_bin/systemctl" <<'SH'
#!/bin/bash
printf 'systemctl\t%s\n' "$*" >>"$BROWSED_LOG"
unit=${*: -1}
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

# lpstat reports the queues cups-browsed generated. Only those route through its
# implicitclass backend; the ipp:// and usb:// entries are printers a person
# added and must survive.
cat >"$mock_bin/lpstat" <<'SH'
#!/bin/bash
printf 'lpstat\t%s\n' "$*" >>"$BROWSED_LOG"
case $1 in
  -v)
    [[ -z $BROWSED_LPSTAT_FAILS ]] || exit 1
    # lpstat translates "device for". Only a caller that pinned the locale gets
    # the string the migration parses.
    if [[ ${LC_ALL:-} == "C" ]]; then
      printf '%s\n' "$BROWSED_QUEUES"
    else
      printf '%s\n' "$BROWSED_QUEUES" | sed 's|^device for |Gerät für |'
    fi
    ;;
  -p)
    # A destination that no longer exists is unknown to lpstat.
    [[ " $BROWSED_GONE_QUEUES " != *" $2 "* ]]
    exit $?
    ;;
  -o)
    [[ -z $BROWSED_LPSTAT_O_FAILS ]] || exit 1
    # Jobs are listed per queue: "<queue>-<id> <user> <size>".
    [[ " $BROWSED_BUSY_QUEUES " == *" $2 "* ]] && printf '%s-7 alice 1024\n' "$2"
    ;;
esac
exit 0
SH

cat >"$mock_bin/lpadmin" <<'SH'
#!/bin/bash
printf 'lpadmin\t%s\n' "$*" >>"$BROWSED_LOG"
[[ -z $BROWSED_LPADMIN_FAILS ]]
SH

cat >"$mock_bin/cupsreject" <<'SH'
#!/bin/bash
printf 'cupsreject\t%s\n' "$*" >>"$BROWSED_LOG"
[[ -z $BROWSED_REJECT_FAILS ]]
SH

chmod +x "$mock_bin"/*

log="$test_tmp/actions.log"
output="$test_tmp/migration.out"
marker="$test_tmp/var/lib/omarchy/migrations/1788009111"

run_migration() {
  : >"$log"
  : >"$output"

  # No LC_ALL in the environment, so the mock above sees "C" only when the
  # migration pinned it for the call itself -- which is what a non-English
  # desktop depends on.
  env -u LC_ALL -u LANGUAGE \
    BROWSED_LOG="$log" \
    BROWSED_INSTALLED="${installed:-}" \
    BROWSED_ENABLED="${enabled:-}" \
    BROWSED_ACTIVE="${active:-}" \
    BROWSED_REMOVAL_BLOCKED="${blocked:-}" \
    BROWSED_QUEUES="${queues:-}" \
    BROWSED_BUSY_QUEUES="${busy:-}" \
    BROWSED_LPSTAT_FAILS="${lpstat_fails:-}" \
    BROWSED_LPADMIN_FAILS="${lpadmin_fails:-}" \
    BROWSED_LPSTAT_O_FAILS="${lpstat_o_fails:-}" \
    BROWSED_REJECT_FAILS="${reject_fails:-}" \
    BROWSED_GONE_QUEUES="${gone_queues:-}" \
    PATH="$mock_bin:$PATH" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_CUPS_BROWSED_REMOVAL_MARKER="${use_marker:-$marker}" \
    bash -euo pipefail "$migration" >"$output"
}

# ------------------------------------------------ a machine that has discovery

installed="cups-browsed"
enabled="cups-browsed.service"
active="cups-browsed.service cups.service"
blocked=""
# CUPS allows a colon in a destination name but never a space, so "Front:Desk"
# is a legal queue and the separator is the last ": implicitclass://".
queues=$'device for Office: implicitclass://Office/\ndevice for Front:Desk: implicitclass://Front:Desk/\ndevice for -p: implicitclass://-p/\ndevice for a,b: implicitclass://a,b/\ndevice for all: implicitclass://all/\ndevice for Desk: ipp://192.168.1.9/ipp/print\ndevice for Attic: usb://HP/LaserJet%20P1102'
rm -f "$marker"
run_migration

grep -qxF $'sudo\tsystemctl disable --now cups-browsed.service' "$log" ||
  fail "the removal disables and stops the discovery service" "$(cat "$log")"
pass "the removal disables and stops the discovery service"

# -Rns would discard /etc/cups/cups-browsed.conf rather than keep it as a
# .pacsave, and a removal meant to be temporary must not delete configuration.
grep -qxF $'pacman\t-R --noconfirm cups-browsed' "$log" ||
  fail "the removal keeps configuration pacman marked as a backup" "$(cat "$log")"
if grep -qE -- '-Rns|-Rn ' "$log"; then
  fail "the removal never passes -n" "$(cat "$log")"
fi
# -s would also sweep dependencies that became unneeded, which is a promise a
# rolling dependency graph cannot keep.
if grep -q -- '-Rs --noconfirm' "$log"; then
  fail "the removal names only the package it means to remove" "$(cat "$log")"
fi
pass "the removal keeps the machine's own cups-browsed.conf and touches nothing else"

# pacman deletes the unit file but not the enable symlink, and once the unit is
# gone systemd cannot resolve it by name to clean that up.
disable_line=$(grep -n 'disable --now' "$log" | tail -1 | cut -d: -f1 || true)
removal_line=$(grep -n $'^pacman\t-R --noconfirm' "$log" | head -1 | cut -d: -f1 || true)
[[ -n $disable_line && -n $removal_line ]] ||
  fail "the removal both disables the unit and removes the package" "$(cat "$log")"
(( disable_line < removal_line )) ||
  fail "the removal disables before the unit file goes" "$(cat "$log")"
pass "the removal disables before the unit file goes"

# cups-browsed keeps its generated queues on shutdown, and they print through
# the implicitclass backend that goes with the package.
grep -qxF $'sudo\tlpadmin -x Office' "$log" ||
  fail "the queues discovery generated are removed with it" "$(cat "$log")"
grep -q 'lpadmin -x Desk' "$log" &&
  fail "a printer added by hand over ipp survives" "$(cat "$log")"
grep -q 'lpadmin -x Attic' "$log" &&
  fail "a printer added by hand over usb survives" "$(cat "$log")"
grep -qxF $'sudo\tlpadmin -x Front:Desk' "$log" ||
  fail "a queue whose name contains a colon is still matched" "$(cat "$log")"

# cups-browsed names queues after what the printer advertised, so the name came
# off the network. lpstat and lpadmin take a destination as an option value: a
# leading dash reads as another option and a comma separates a list.
if grep -qF -- $'lpstat\t-o -p' "$log"; then
  fail "a queue named like an option is never passed to lpstat" "$(cat "$log")"
fi
if grep -q -- 'lpadmin -x -p' "$log"; then
  fail "a queue named like an option is never passed to lpadmin" "$(cat "$log")"
fi
if grep -q 'lpadmin -x a,b' "$log"; then
  fail "a queue name holding a comma is never passed as a destination list" "$(cat "$log")"
fi
if grep -qF -- $'lpstat\t-o all' "$log"; then
  fail "a queue named all is never asked about, since lpstat reads it as every destination" "$(cat "$log")"
fi
grep -qF -- "Cannot safely ask about jobs on the queue named '-p'" "$output" ||
  fail "a queue that cannot be asked about safely is reported" "$(cat "$output")"
pass "generated queues go, hand-added printers stay, unaddressable names are reported"

# The queues have to go while cups-browsed's backend is still installed.
cleanup_line=$(grep -n 'lpadmin -x' "$log" | tail -1 | cut -d: -f1 || true)
[[ -n $cleanup_line ]] || fail "the removal cleans up generated queues" "$(cat "$log")"
(( cleanup_line < removal_line )) ||
  fail "generated queues go before the backend that serves them" "$(cat "$log")"
pass "generated queues go before the backend that serves them"

[[ -f $marker ]] || fail "the removal records machine-wide completion"
pass "the removal records machine-wide completion"

# ------------------------------------ a second user, after a deliberate reinstall

# Migration state is per user. The account that runs this after someone put
# discovery back on purpose must not quietly take it away again.
installed="cups-browsed"
enabled="cups-browsed.service"
active="cups-browsed.service cups.service"
run_migration

[[ ! -s $log ]] || fail "a machine that already had its removal is left alone" "$(cat "$log")"
pass "a second user does not undo a deliberate reinstall"

# ----------------------------------------- a machine that never had discovery

installed=""
enabled=""
active="cups.service"
use_marker="$test_tmp/var/lib/omarchy/migrations/never-had-it"
run_migration

[[ ! -s $log ]] || fail "a machine without discovery is left alone" "$(cat "$log")"
[[ ! -e $use_marker ]] ||
  fail "a machine with nothing to remove is not made to pay for a marker" "$(cat "$log")"
pass "a machine without discovery does no privileged work and gets no password prompt"

# ------------------------------------------------- a blocked package removal

# Something depending on cups-browsed makes pacman refuse. Stopping the service
# first and only then discovering that would leave discovery broken rather than
# removed.
installed="cups-browsed"
enabled="cups-browsed.service"
active="cups-browsed.service cups.service"
blocked="1"
use_marker="$test_tmp/var/lib/omarchy/migrations/blocked"
run_migration

grep -q 'disable --now' "$log" &&
  fail "a refused removal never stops the service" "$(cat "$log")"
if grep -q $'^pacman\t-R --noconfirm' "$log"; then
  fail "a refused removal does not go on to remove anything" "$(cat "$log")"
fi
[[ ! -e $use_marker ]] || fail "a refused removal is not recorded as done"
# The preflight has to ask about the same command the removal will run.
grep -qxF $'pacman\t-R --print cups-browsed' "$log" ||
  fail "the preflight asks pacman about the removal it will actually run" "$(cat "$log")"
pass "a removal pacman would refuse changes nothing at all"

# --------------------------------------------------- a queue that is printing

# lpadmin -x cancels the jobs on the queue it removes. A stale queue can be
# deleted whenever someone notices it; an aborted print cannot come back.
installed="cups-browsed"
enabled="cups-browsed.service"
active="cups-browsed.service cups.service"
blocked=""
queues=$'device for Office: implicitclass://Office/\ndevice for Spare: implicitclass://Spare/'
busy="Office"
use_marker="$test_tmp/var/lib/omarchy/migrations/printing"
run_migration

# The implicitclass backend only needs cups-browsed to choose a destination, so
# a job already past that point finishes even though the daemon has stopped.
# Deleting the queue would abort it.
if grep -q 'lpadmin -x Office' "$log"; then
  fail "a queue with jobs on it is left for them to finish" "$(cat "$log")"
fi
grep -qxF $'sudo\tlpadmin -x Spare' "$log" ||
  fail "an idle generated queue is still removed" "$(cat "$log")"

# A job submitted between the check and the deletion -- the sudo in between can
# sit at a password prompt -- would be cancelled by a deletion that had decided
# the queue was empty.
reject_line=$(grep -n 'cupsreject.*Spare' "$log" | head -1 | cut -d: -f1 || true)
probe_line=$(grep -n $'^lpstat\t-o Spare' "$log" | head -1 | cut -d: -f1 || true)
delete_line=$(grep -n 'lpadmin -x Spare' "$log" | head -1 | cut -d: -f1 || true)
[[ -n $reject_line && -n $probe_line && -n $delete_line ]] ||
  fail "a queue is closed, inspected and removed in that order" "$(cat "$log")"
(( reject_line < probe_line && probe_line < delete_line )) ||
  fail "a queue stops taking new jobs before it is inspected or removed" "$(cat "$log")"
pass "a queue stops taking new jobs before it is inspected or removed"

grep -q 'Office still has jobs' "$output" ||
  fail "a queue left alone is named so it can be removed later" "$(cat "$output")"
# One printer's job must not keep discovery on the machine.
grep -qxF $'sudo\tpacman -R --noconfirm cups-browsed' "$log" ||
  fail "a busy queue does not hold up the removal" "$(cat "$log")"
pass "a queue with jobs is left for them to finish, and does not hold up the removal"

# ------------------------------------------------- a job query that fails

# Treating a failed query as an idle queue would delete it and abort whatever
# was on it, which is the one outcome this is trying to avoid.
lpstat_o_fails="1"
use_marker="$test_tmp/var/lib/omarchy/migrations/nojobs"
run_migration

if grep -q 'lpadmin -x' "$log"; then
  fail "a queue whose jobs could not be checked is left alone" "$(cat "$log")"
fi
grep -q 'Could not check for jobs' "$output" ||
  fail "a job query that failed is said out loud" "$(cat "$output")"
pass "a queue whose jobs cannot be checked is left alone, not assumed idle"

lpstat_o_fails=""

# ------------------------------------------------------ CUPS out of reach

# Failing to reach cupsd must not read like a machine with no queues to clean.
installed="cups-browsed"
enabled="cups-browsed.service"
active="cups-browsed.service"
busy=""
lpstat_fails="1"
use_marker="$test_tmp/var/lib/omarchy/migrations/nocups"
run_migration

if grep -q 'lpadmin -x' "$log"; then
  fail "nothing is removed when the queue list could not be read" "$(cat "$log")"
fi
# Removing the backend without having read the queue list would strand every
# generated queue permanently, and the marker would stop anyone retrying.
if grep -q $'^pacman\t-R --noconfirm' "$log"; then
  fail "the package waits until the queue list can be read" "$(cat "$log")"
fi
[[ ! -e $use_marker ]] ||
  fail "an unread queue list is not recorded as a finished removal"
grep -qi 'could not ask cups' "$output" ||
  fail "a queue list that could not be read is said out loud" "$(cat "$output")"
# Stopping discovery is the half that mattered, and it is idempotent.
grep -qxF $'sudo\tsystemctl disable --now cups-browsed.service' "$log" ||
  fail "discovery is still stopped when the queue list cannot be read" "$(cat "$log")"
pass "an unreadable queue list stops discovery but finalizes nothing"

lpstat_fails=""

# ------------------------------------------------ a queue that will not go

# A queue left behind would route through a backend the removal is about to
# delete, so the package waits rather than stranding it for good.
installed="cups-browsed"
enabled="cups-browsed.service"
active="cups-browsed.service cups.service"
blocked=""
queues=$'device for Office: implicitclass://Office/'
busy=""
lpstat_fails=""
lpadmin_fails="1"
use_marker="$test_tmp/var/lib/omarchy/migrations/stuck"
run_migration

if grep -q $'^pacman\t-R --noconfirm' "$log"; then
  fail "the package waits while a generated queue is still there" "$(cat "$log")"
fi
[[ ! -e $use_marker ]] || fail "a half-done cleanup is not recorded as finished"
grep -q 'Could not remove the queue Office' "$output" ||
  fail "a queue that would not go is named" "$(cat "$output")"
pass "a queue that will not go keeps the package and the marker back"

lpadmin_fails=""

# --------------------------------------------- a queue removed by someone else

# Another administrator deleting the queue mid-run is the outcome wanted, not a
# failure worth keeping the package installed for.
installed="cups-browsed"
enabled="cups-browsed.service"
active="cups-browsed.service cups.service"
blocked=""
queues=$'device for Office: implicitclass://Office/'
busy=""
lpstat_fails=""
lpstat_o_fails=""
lpadmin_fails="1"
gone_queues="Office"
use_marker="$test_tmp/var/lib/omarchy/migrations/vanished"
run_migration

grep -qxF $'sudo\tpacman -R --noconfirm cups-browsed' "$log" ||
  fail "a queue that is already gone does not hold up the removal" "$(cat "$log")"
[[ -f $use_marker ]] || fail "a queue that is already gone still finishes the migration"
pass "a queue someone else removed counts as removed"

lpadmin_fails=""
gone_queues=""

# ------------------------------------------- a queue that will not stop taking jobs

# Deleting a queue that is still accepting work races whatever arrives next.
installed="cups-browsed"
enabled="cups-browsed.service"
active="cups-browsed.service cups.service"
reject_fails="1"
use_marker="$test_tmp/var/lib/omarchy/migrations/openqueue"
run_migration

if grep -q 'lpadmin -x' "$log"; then
  fail "a queue still accepting jobs is not deleted" "$(cat "$log")"
fi
if grep -q $'^pacman\t-R --noconfirm' "$log"; then
  fail "the package waits while a queue is still accepting jobs" "$(cat "$log")"
fi
[[ ! -e $use_marker ]] || fail "a queue still taking jobs is not recorded as done"
pass "a queue that will not stop taking jobs is neither inspected nor deleted"

reject_fails=""

# -------------------------------------------------- a masked but running daemon

installed="cups-browsed"
enabled=""
active="cups-browsed.service"
blocked=""
queues=""
use_marker="$test_tmp/var/lib/omarchy/migrations/masked"
run_migration

grep -qxF $'sudo\tsystemctl stop cups-browsed.service' "$log" ||
  fail "a running unit is stopped even when it is not enabled" "$(cat "$log")"
grep -q 'disable --now' "$log" &&
  fail "a masked unit is not disabled" "$(cat "$log")"
pass "a masked but running daemon is stopped without being disabled"

# A machine whose discovery never created a queue has nothing to clean up, and
# no reason to reach for CUPS administration.
grep -q 'lpadmin' "$log" &&
  fail "no queues means no CUPS administration" "$(cat "$log")"
pass "a machine with no generated queues does not touch CUPS administration"
