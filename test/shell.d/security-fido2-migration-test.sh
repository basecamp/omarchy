#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1787494718.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
stages="$test_tmp/stages.log"
notifications="$test_tmp/notifications.log"
# A directory of its own, not $test_tmp: the migration derives the FIDO2
# directory from the authfile, and the case below where that directory is
# untraversable has to be able to take the permissions off it.
authdir="$test_tmp/etc-fido2"
authfile="$authdir/fido2"
migration_copy="$test_tmp/migration.sh"
mkdir -p "$stub_bin" "$authdir"
: >"$stages"
: >"$notifications"

# The migration repairs an absolute path no unprivileged suite can write, and an
# environment override in the shipped file would hand a root install and mv an
# operand the caller chooses. Retarget a scratch copy instead, and fail if the
# path is not named exactly once, so this seam cannot quietly stop standing for
# the file it copies.
occurrences=$(grep -Fo /etc/fido2/fido2 "$migration" | wc -l) || occurrences=0
(( occurrences == 1 )) ||
  fail "the migration names its authfile exactly once, so the test can retarget a copy" \
    "found $occurrences occurrences"
grep -Fxq 'authfile="/etc/fido2/fido2"' "$migration" ||
  fail "the production authfile path is a fixed literal, not caller-controlled"
pass "migration names its authfile once, and the test drives a retargeted copy"

# Log every escalation, then execute only the expected bare sudo forms. Each
# operand is matched against the scratch authfile or a stage this stub created.
# This contains malformed calls made through that interface; arbitrary direct
# privileged commands in the migration are outside this harness.
cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

set -euo pipefail

reject() {
  printf 'refusing unexpected sudo invocation:' >&2
  printf ' %q' "$@" >&2
  printf '\n' >&2
  exit 97
}

if [[ ${TEST_TMP:-} != /* || ${TEST_AUTHDIR:-} != "$TEST_TMP/etc-fido2" || ${TEST_AUTHFILE:-} != "$TEST_AUTHDIR/fido2" || ${TEST_LOG:-} != "$TEST_TMP/calls.log" || ${TEST_STAGES:-} != "$TEST_TMP/stages.log" ]]; then
  reject "$@"
fi

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"

safe_stage_path() {
  local candidate=$1
  local prefix="$TEST_AUTHFILE.new."
  local suffix

  [[ $candidate == "$prefix"* ]] || return 1
  suffix=${candidate#"$prefix"}
  [[ $suffix =~ ^[[:alnum:]]{6}$ ]]
}

recorded_stage() {
  local candidate=$1

  safe_stage_path "$candidate" || return 1
  [[ -f $candidate && ! -L $candidate ]] || return 1
  /usr/bin/grep -Fxq -- "$candidate" "$TEST_STAGES"
}

case "$1" in
  mktemp)
    if (( $# != 2 )) || [[ $2 != "$TEST_AUTHFILE.new.XXXXXX" ]]; then
      reject "$@"
    fi

    case ${TEST_MKTEMP_MODE:-normal} in
      normal)
        stage=$(/usr/bin/mktemp -- "$2")
        if ! safe_stage_path "$stage" || [[ ! -f $stage || -L $stage ]]; then
          reject "$@"
        fi

        printf '%s\n' "$stage" >>"$TEST_STAGES"
        printf '%s\n' "$stage"
        ;;
      malformed)
        stage="$TEST_AUTHFILE.new.A/BCDE"
        /usr/bin/mkdir -- "${stage%/*}"
        : >"$stage"
        printf '%s\n' "$stage"
        ;;
      nonregular)
        stage="$TEST_AUTHFILE.new.BAD123"
        /usr/bin/mkdir -- "$stage"
        printf '%s\n' "$stage"
        ;;
      *)
        reject "$@"
        ;;
    esac
    ;;
  install)
    if (( $# != 10 )) || [[ $2 != "-T" || $3 != "-m" || $4 != "644" || $5 != "-o" || $6 != "root" || $7 != "-g" || $8 != "root" || $9 != "$TEST_AUTHFILE" ]] || ! recorded_stage "${10}"; then
      reject "$@"
    fi

    if [[ ${TEST_FAIL_INSTALL:-0} == "1" ]]; then
      exit 71
    fi

    if (( EUID == 0 )); then
      exec /usr/bin/install -T -m 644 -o root -g root "$9" "${10}"
    else
      exec /usr/bin/install -T -m 644 "$9" "${10}"
    fi
    ;;
  mv)
    if (( $# != 4 )) || [[ $2 != "-Tf" || $4 != "$TEST_AUTHFILE" ]] || ! recorded_stage "$3"; then
      reject "$@"
    fi

    if [[ ${TEST_FAIL_MV:-0} == "1" ]]; then
      exit 72
    fi

    exec /usr/bin/mv -Tf -- "$3" "$4"
    ;;
  chmod)
    # Only ever the FIDO2 directory, and only back to the mode the setup
    # installs. Nothing here may reopen the authfile itself.
    if (( $# != 3 )) || [[ $2 != "755" || $3 != "$TEST_AUTHDIR" ]]; then
      reject "$@"
    fi

    exec /usr/bin/chmod 755 "$TEST_AUTHDIR"
    ;;
  test)
    # Looking behind an untraversable directory, never a write. This stub is not
    # really root, so open the directory just long enough to answer the way root
    # would and put its mode straight back -- the suite then still sees whether
    # production left the mode alone.
    if (( $# != 3 )) || [[ $2 != "-e" && $2 != "-L" ]] || [[ $3 != "$TEST_AUTHFILE" ]]; then
      reject "$@"
    fi

    saved_mode=$(/usr/bin/stat -c %a "$TEST_AUTHDIR")
    /usr/bin/chmod 755 "$TEST_AUTHDIR"
    probe_status=0
    /usr/bin/test "$2" "$3" || probe_status=$?
    /usr/bin/chmod "$saved_mode" "$TEST_AUTHDIR"
    exit "$probe_status"
    ;;
  rm)
    if (( $# != 4 )) || [[ $2 != "-f" || $3 != "--" ]]; then
      reject "$@"
    fi

    if [[ ${TEST_MKTEMP_MODE:-normal} == "nonregular" && $4 == "$TEST_AUTHFILE.new.BAD123" && -d $4 && ! -L $4 ]]; then
      exit 73
    fi

    recorded_stage "$4" || reject "$@"
    exec /usr/bin/rm -f -- "$4"
    ;;
  *)
    reject "$@"
    ;;
esac
SH

chmod +x "$stub_bin/sudo"

cat >"$stub_bin/stat" <<'SH'
#!/bin/bash

set -euo pipefail

if [[ ${TEST_FAKE_STAT:-0} == "1" && ${TEST_AUTHFILE:-} == "${TEST_AUTHDIR:-}/fido2" ]] &&
  (( $# == 3 )) && [[ $1 == "-c" && $3 == "$TEST_AUTHFILE" ]]; then
  case "$2" in
    %U) printf '%s\n' "$TEST_STAT_OWNER" ;;
    %G) printf '%s\n' "$TEST_STAT_GROUP" ;;
    %a) printf '%s\n' "$TEST_STAT_MODE" ;;
    *) exec /usr/bin/stat "$@" ;;
  esac
else
  exec /usr/bin/stat "$@"
fi
SH

chmod +x "$stub_bin/stat"

# omarchy-migrate records this migration complete on any zero exit, so the
# states it cannot repair have to reach the user somewhere that outlives the
# update terminal's scrollback.
cat >"$stub_bin/omarchy-notification-send" <<'SH'
#!/bin/bash

printf 'notify' >>"$TEST_NOTIFICATIONS"
printf '\t%s' "$@" >>"$TEST_NOTIFICATIONS"
printf '\n' >>"$TEST_NOTIFICATIONS"
exit "${TEST_NOTIFY_STATUS:-0}"
SH

chmod +x "$stub_bin/omarchy-notification-send"

run_migration() {
  local fail_install="${1:-0}"
  local fail_mv="${2:-0}"
  local stat_owner="${3:-}"
  local stat_group="${4:-}"
  local stat_mode="${5:-}"
  local mktemp_mode="${6:-normal}"
  local notify_status="${7:-0}"
  local fake_stat=0

  if [[ -n $stat_owner || -n $stat_group || -n $stat_mode ]]; then
    [[ -n $stat_owner && -n $stat_group && -n $stat_mode ]] ||
      fail "a fake stat fixture supplies owner, group and mode together"
    fake_stat=1
  fi

  : >"$calls"
  : >"$notifications"
  sed "s|/etc/fido2/fido2|$authfile|" "$migration" >"$migration_copy"

  PATH="$stub_bin:$PATH" TEST_AUTHDIR="$authdir" TEST_AUTHFILE="$authfile" \
    TEST_FAIL_INSTALL="$fail_install" TEST_FAIL_MV="$fail_mv" TEST_FAKE_STAT="$fake_stat" \
    TEST_LOG="$calls" TEST_MKTEMP_MODE="$mktemp_mode" TEST_NOTIFICATIONS="$notifications" \
    TEST_NOTIFY_STATUS="$notify_status" TEST_STAGES="$stages" TEST_STAT_GROUP="$stat_group" \
    TEST_STAT_MODE="$stat_mode" TEST_STAT_OWNER="$stat_owner" TEST_TMP="$test_tmp" \
    bash -euo pipefail "$migration_copy" >/dev/null
}

safe_fixture_stage_path() {
  local candidate=$1
  local prefix="$authfile.new."
  local suffix

  [[ $candidate == "$prefix"* ]] || return 1
  suffix=${candidate#"$prefix"}
  [[ $suffix =~ ^[[:alnum:]]{6}$ ]]
}

# Every repair case is about an authfile its own user can still rewrite. The
# calls below give stat an explicit caller-owned state, so the same assertions
# work as an ordinary user, as real root, and in a namespace mapping only UID 0.
write_authfile() {
  printf 'tester:credential-handle,public-key,es256,+presence\n' >"$authfile"
  chmod "$1" "$authfile"
}

# Almost every machine has never registered a key, and establishing that must
# not cost those users a password prompt.
rm -f "$authfile"
run_migration
[[ ! -s $calls ]] || fail "a machine with no authfile escalates nothing" "$(cat "$calls")"
pass "migration skips a machine that never set FIDO2 up"

# What the old `sudo mv` left behind on every machine that did: the authfile PAM
# consults for sudo, owned by the account it authenticates, at the caller's umask.
write_authfile 644 || fail "the test can stage a non-root-owned authfile"
before_inode=$(stat -c %i "$authfile")
run_migration 0 0 caller caller 644

grep -Fq $'sudo\tmktemp\t'"$authfile.new.XXXXXX" "$calls" ||
  fail "the repair asks root for a unique sibling stage" "$(cat "$calls")"
grep -Fq $'sudo\tinstall\t-T\t-m\t644\t-o\troot\t-g\troot\t'"$authfile"$'\t' "$calls" ||
  fail "a user-owned authfile is reinstalled root:root and mode 644" "$(cat "$calls")"
grep -Fq $'sudo\tmv\t-Tf\t' "$calls" ||
  fail "the staged authfile is atomically renamed over the live path" "$(cat "$calls")"
if grep -Fq $'sudo\tchown\t' "$calls"; then
  fail "the repair replaces the authfile rather than chowning it" "$(cat "$calls")"
fi
if grep -Fq $'sudo\trm\t' "$calls"; then
  fail "a successful repair disarms its EXIT cleanup" "$(cat "$calls")"
fi
pass "migration stages and atomically installs a root-owned authfile"

[[ $(stat -c %a "$authfile") == "644" ]] ||
  fail "the repaired authfile is mode 644" "got: $(stat -c %a "$authfile")"
[[ $(cat "$authfile") == "tester:credential-handle,public-key,es256,+presence" ]] ||
  fail "the repaired authfile keeps its credential" "got: $(cat "$authfile")"
if (( EUID == 0 )) && [[ $(stat -c %U:%G "$authfile") != "root:root" ]]; then
  fail "the repaired authfile is root:root" "got: $(stat -c %U:%G "$authfile")"
fi
pass "migration preserves the credential with its PAM-readable mode"

# The whole point of replacing rather than chowning. Permission is checked at
# open(2), so a descriptor the registering user opened before the update stays
# writable on the old inode through any chmod or chown -- and pam_u2f resolving
# the authfile path would keep reading exactly that inode.
[[ $(stat -c %i "$authfile") != "$before_inode" ]] ||
  fail "the repair lands on a new inode, orphaning any descriptor already open on the old one"
pass "migration replaces the inode a pre-existing writer would still hold"

mapfile -t staged_paths <"$stages"
(( ${#staged_paths[@]} == 1 )) ||
  fail "the first repair creates exactly one stage" "got: ${staged_paths[*]}"
first_stage=${staged_paths[0]}
safe_fixture_stage_path "$first_stage" ||
  fail "the stage is a unique sibling of the authfile" "got: $first_stage"
[[ ! -e $first_stage && ! -L $first_stage ]] ||
  fail "the staged copy does not outlive the repair" "left behind: $first_stage"
pass "migration uses a unique sibling and leaves no staged copy behind"

# Treat mktemp's output as untrusted even though sudo normally resolves the
# system binary. This existing regular path has a six-character suffix only if
# `/` is accepted as one of the characters, as the old ?????? glob did. The
# strict shape check must reject it before any privileged write or cleanup.
write_authfile 644 || fail "the test can stage the malformed-output fixture"
before_inode=$(stat -c %i "$authfile")
malformed_parent="$authfile.new.A"
malformed_stage="$malformed_parent/BCDE"
if run_migration 0 0 caller caller 644 malformed; then
  fail "malformed mktemp output fails the migration"
fi

grep -Fq $'sudo\tmktemp\t' "$calls" ||
  fail "the malformed-output fixture reaches mktemp" "$(cat "$calls")"
if grep -Fq $'sudo\tinstall\t' "$calls" || grep -Fq $'sudo\tmv\t' "$calls" || grep -Fq $'sudo\trm\t' "$calls"; then
  fail "malformed mktemp output reaches no install, rename or cleanup" "$(cat "$calls")"
fi
[[ $(stat -c %i "$authfile") == "$before_inode" ]] ||
  fail "malformed mktemp output leaves the live authfile inode alone"
[[ -f $malformed_stage && ! -L $malformed_stage ]] ||
  fail "the malformed-output fixture remains a regular scratch file" "got: $malformed_stage"
/usr/bin/rm -- "$malformed_stage"
/usr/bin/rmdir -- "$malformed_parent"
pass "migration rejects malformed mktemp output before any privileged write"

# A name can have the right prefix and six-character suffix but still name an
# object mktemp would never return. Production must reject that object before
# install/mv; its cleanup may address only that validated scratch sibling and
# must not recursively remove the unexpected directory.
write_authfile 644 || fail "the test can stage the nonregular-output fixture"
before_inode=$(stat -c %i "$authfile")
nonregular_stage="$authfile.new.BAD123"
if run_migration 0 0 caller caller 644 nonregular; then
  fail "nonregular mktemp output fails the migration"
fi

safe_fixture_stage_path "$nonregular_stage" ||
  fail "the nonregular fixture uses a syntactically valid stage name" "got: $nonregular_stage"
if grep -Fq $'sudo\tinstall\t' "$calls" || grep -Fq $'sudo\tmv\t' "$calls"; then
  fail "nonregular mktemp output is rejected before install or rename" "$(cat "$calls")"
fi
grep -Fq $'sudo\trm\t-f\t--\t'"$nonregular_stage" "$calls" ||
  fail "cleanup addresses only the validated nonregular sibling" "$(cat "$calls")"
[[ -d $nonregular_stage && ! -L $nonregular_stage ]] ||
  fail "cleanup does not recursively remove a nonregular stage" "got: $nonregular_stage"
[[ $(stat -c %i "$authfile") == "$before_inode" ]] ||
  fail "nonregular mktemp output leaves the live authfile inode alone"
/usr/bin/rmdir -- "$nonregular_stage"
pass "migration rejects and safely handles nonregular mktemp output"

# A caller-owned file still needs a fresh inode and root ownership whatever its
# current mode.
write_authfile 600 || fail "the test can restage a non-root-owned authfile"
run_migration 0 0 caller caller 600
grep -Fq $'sudo\tinstall\t-T\t' "$calls" ||
  fail "a mode-600 authfile the user still owns is repaired" "$(cat "$calls")"

mapfile -t staged_paths <"$stages"
(( ${#staged_paths[@]} == 2 )) ||
  fail "two repairs create two stages" "got: ${staged_paths[*]}"
second_stage=${staged_paths[1]}
[[ ! -e $second_stage && ! -L $second_stage ]] ||
  fail "the second staged copy does not outlive the repair" "left behind: $second_stage"
pass "migration repairs a user-owned authfile whatever its mode and cleans its stage"

# A failure after mktemp must remove only the exact stage the stub created. The
# live authfile stays on its original inode because mv was never reached.
write_authfile 644 || fail "the test can stage the cleanup fixture"
before_inode=$(stat -c %i "$authfile")
if run_migration 1 0 caller caller 644; then
  fail "an install failure propagates out of the migration"
fi

mapfile -t staged_paths <"$stages"
(( ${#staged_paths[@]} == 3 )) ||
  fail "the failed repair creates one stage" "got: ${staged_paths[*]}"
failed_stage=${staged_paths[2]}
grep -Fq $'sudo\trm\t-f\t--\t'"$failed_stage" "$calls" ||
  fail "the EXIT trap removes the failed repair's exact stage" "$(cat "$calls")"
[[ ! -e $failed_stage && ! -L $failed_stage ]] ||
  fail "the failed stage is cleaned up" "left behind: $failed_stage"
[[ $(stat -c %i "$authfile") == "$before_inode" ]] ||
  fail "a failed repair leaves the live authfile inode alone"
pass "migration cleans its unique stage after a failed repair"

# A failure after install has the same cleanup obligation. In particular, the
# EXIT trap must still be armed when mv fails.
write_authfile 644 || fail "the test can stage the mv-failure fixture"
before_inode=$(stat -c %i "$authfile")
if run_migration 0 1 caller caller 644; then
  fail "an mv failure propagates out of the migration"
fi

mapfile -t staged_paths <"$stages"
(( ${#staged_paths[@]} == 4 )) ||
  fail "the mv-failed repair creates one stage" "got: ${staged_paths[*]}"
failed_mv_stage=${staged_paths[3]}
grep -Fq $'sudo\tmv\t-Tf\t'"$failed_mv_stage"$'\t'"$authfile" "$calls" ||
  fail "the injected mv failure occurs after install" "$(cat "$calls")"
grep -Fq $'sudo\trm\t-f\t--\t'"$failed_mv_stage" "$calls" ||
  fail "the EXIT trap removes the mv-failed repair's exact stage" "$(cat "$calls")"
[[ ! -e $failed_mv_stage && ! -L $failed_mv_stage ]] ||
  fail "the mv-failed stage is cleaned up" "left behind: $failed_mv_stage"
[[ $(stat -c %i "$authfile") == "$before_inode" ]] ||
  fail "an mv failure leaves the live authfile inode alone"
pass "migration cleans its unique stage after a failed rename"

# The state a completed repair leaves, which is also where every machine that
# registers after this fix starts. A second account, and a second run for the
# same account, must find it done and escalate nothing. Fake only stat's view of
# the scratch authfile so this stays deterministic without borrowing a host
# file or requiring the suite itself to run as root.
write_authfile 644 || fail "the test can stage the settled-state fixture"
run_migration 0 0 root root 644
[[ ! -s $calls ]] ||
  fail "an already root:root mode-644 authfile escalates nothing" "$(cat "$calls")"
pass "migration deterministically no-ops on its settled state"

# Owner, group and mode are independent parts of that state check. Hold two at
# their settled values while making each third value wrong, and require repair.
write_authfile 644 || fail "the test can stage the wrong-owner fixture"
run_migration 0 0 nobody root 644
grep -Fq $'sudo\tinstall\t-T\t' "$calls" ||
  fail "a non-root-owned authfile is repaired even when group and mode are settled" "$(cat "$calls")"
pass "migration repairs an authfile with the wrong owner"

write_authfile 644 || fail "the test can stage the wrong-group fixture"
run_migration 0 0 root nobody 644
grep -Fq $'sudo\tinstall\t-T\t' "$calls" ||
  fail "a non-root-group authfile is repaired even when owner and mode are settled" "$(cat "$calls")"
pass "migration repairs an authfile with the wrong group"

write_authfile 644 || fail "the test can stage the wrong-mode fixture"
run_migration 0 0 root root 600
grep -Fq $'sudo\tinstall\t-T\t' "$calls" ||
  fail "a mode-600 authfile is repaired even when owner and group are settled" "$(cat "$calls")"
pass "migration repairs an authfile with the wrong mode"

# Neither of these is ours to rewrite, and both must say so without escalating:
# chown follows a symlink and would take the target instead, while changing a
# directory's mode would alter an object the migration does not own.
rm -rf "$authfile"
ln -s "$test_tmp/elsewhere" "$authfile"
: >"$test_tmp/elsewhere"
run_migration
[[ ! -s $calls ]] || fail "a symlinked authfile escalates nothing" "$(cat "$calls")"
[[ -s $notifications ]] ||
  fail "a symlinked authfile is raised where the update terminal cannot swallow it"

rm -f "$authfile"
ln -s "$test_tmp/missing" "$authfile"
run_migration
[[ ! -s $calls ]] || fail "a dangling symlink escalates nothing" "$(cat "$calls")"
[[ -s $notifications ]] || fail "a dangling symlink is raised the same way"
pass "migration reports a symlinked authfile and repairs nothing"

rm -f "$authfile"
mkdir -p "$authfile"
run_migration
[[ ! -s $calls ]] || fail "a directory at the authfile path escalates nothing" "$(cat "$calls")"
[[ -s $notifications ]] || fail "a non-regular authfile is raised the same way"
pass "migration reports a non-regular authfile and repairs nothing"

# omarchy-migrate writes this migration's completion marker on any zero exit, so
# a machine it cannot repair gets one shot at telling the user. The states above
# are exactly the ones where the authfile may already be under someone else's
# control, and a line in the update terminal scrolls past.
# Assert the argument shape rather than a substring. The glyph is a private-use
# codepoint that an edit can silently drop, and losing it shifts every argument
# left: -g swallows the headline, the body becomes the title, and the message
# goes out with no description. A substring match sees all of that as fine.
awk -F'\t' '
  $1 == "notify" && NF == 7 && $2 == "-u" && $3 == "critical" && $4 == "-g" &&
    $5 != "" && $6 == "FIDO2 authfile needs attention" && $7 != "" { found = 1 }
  END { exit !found }
' "$notifications" ||
  fail "the notification passes a glyph, headline and body as separate arguments" \
    "$(cat -A "$notifications")"
pass "migration raises its unrepairable states as a desktop notification"

# The old setup created the FIDO2 directory with `sudo mkdir -p`, which took the
# caller's umask: registering under `umask 077` left it mode 0700 with the
# user-owned authfile still inside. Absence and "cannot look" are the same
# answer to an unprivileged test, so keying the early exit on the authfile
# recorded a repair on exactly the machines that still needed one.
rm -rf "$authfile"
write_authfile 644 || fail "the test can stage the untraversable-directory fixture"
before_inode=$(stat -c %i "$authfile")
chmod 000 "$authdir"
run_migration 0 0 caller caller 644
[[ $(stat -c %a "$authdir") == "755" ]] ||
  fail "the migration reopens the directory the old umask closed" "got: $(stat -c %a "$authdir")"
grep -Fxq $'sudo\tchmod\t755\t'"$authdir" "$calls" ||
  fail "the migration asks root to reopen the FIDO2 directory" "$(cat "$calls")"
grep -Fq $'sudo\tinstall\t-T\t' "$calls" ||
  fail "an authfile hidden behind an untraversable directory is still repaired" "$(cat "$calls")"
[[ $(stat -c %i "$authfile") != "$before_inode" ]] ||
  fail "the repair behind an untraversable directory still replaces the inode"
pass "migration repairs an authfile an unreadable directory hid from it"

# The narrow escalation above must not reach a machine that never registered a
# key, which is almost all of them.
rm -f "$authfile"
rm -rf "$authdir"
run_migration
[[ ! -s $calls ]] ||
  fail "a machine with no FIDO2 directory still escalates nothing" "$(cat "$calls")"
mkdir -p "$authdir"
run_migration
[[ ! -s $calls ]] ||
  fail "an empty readable FIDO2 directory escalates nothing" "$(cat "$calls")"
pass "migration still costs no password prompt on a machine that never set FIDO2 up"

# An aborted setup can leave the directory behind with nothing in it, and an
# administrator may keep one deliberately private. Looking costs a probe, but
# neither may have its mode widened, or its group and special bits discarded,
# for a repair that is not needed.
rm -f "$authfile"
chmod 000 "$authdir"
run_migration
[[ $(stat -c %a "$authdir") == "0" ]] ||
  fail "an empty inaccessible FIDO2 directory keeps its mode" "got: $(stat -c %a "$authdir")"
! grep -Fq $'sudo\tchmod\t' "$calls" ||
  fail "an empty inaccessible FIDO2 directory is never reopened" "$(cat "$calls")"
if grep -Fq $'sudo\tinstall\t' "$calls" || grep -Fq $'sudo\tmv\t' "$calls"; then
  fail "an empty inaccessible FIDO2 directory is never repaired" "$(cat "$calls")"
fi
chmod 755 "$authdir"
pass "migration looks behind an inaccessible FIDO2 directory without widening it"

# Notification delivery fails on a machine with no user bus or no notification
# server. That must not abort the migration under `bash -euo pipefail` and take
# every later migration with it.
rm -f "$authfile"
ln -s "$test_tmp/missing" "$authfile"
run_migration 0 0 "" "" "" normal 1
[[ -s $notifications ]] ||
  fail "the failing notification was still attempted" "$(cat "$notifications")"
pass "migration survives a notification it could not deliver"
rm -f "$authfile"
