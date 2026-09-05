#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

setup="$ROOT/bin/omarchy-setup-security-fido2"

test_tmp=$(mktemp -d)
stub_bin="$test_tmp/bin"
stages="$test_tmp/stages.log"
calls="$test_tmp/calls.log"
pamu_targets="$test_tmp/pamu-targets.log"
pamu_args="$test_tmp/pamu-args.log"
output="$test_tmp/output.log"
bare_mktemp="$test_tmp/bare-mktemp.log"
credential="tester:credential-handle,public-key,es256,+presence"
authdir="$test_tmp/etc-fido2"
authfile="$authdir/fido2"
setup_copy="$test_tmp/setup.sh"
default_token_info='options: rk, up, noplat, clientPin, pinUvAuthToken'
token_info=$default_token_info
token_info_fails=0
mkdir -p "$stub_bin"

cleanup() {
  rm -rf "$test_tmp"
  return 0
}
trap cleanup EXIT

# The setup installs to an absolute path no unprivileged suite can write, and an
# environment override in the shipped command would hand its privileged install
# and mv an operand the caller chooses. Retarget a scratch copy instead, and
# fail if either path is not named exactly once, so this seam cannot quietly
# stop standing for the command it copies. Keying the suite on the host's own
# /etc/fido2 instead is what let the staging checks below pass without asserting
# anything on the machines that actually use FIDO2.
occurrences=$(grep -Fxc 'authdir=/etc/fido2' "$setup") || occurrences=0
(( occurrences == 1 )) ||
  fail "the setup names its FIDO2 directory exactly once" "found $occurrences occurrences"
occurrences=$(grep -Fxc 'authfile=/etc/fido2/fido2' "$setup") || occurrences=0
(( occurrences == 1 )) ||
  fail "the setup names its authfile exactly once" "found $occurrences occurrences"
pass "setup names its FIDO2 paths once each, and the test drives a retargeted copy"

sed -e "s|^authdir=/etc/fido2$|authdir=$authdir|" \
  -e "s|^authfile=/etc/fido2/fido2$|authfile=$authfile|" "$setup" >"$setup_copy"

# The setup must not create a caller-owned named file for pamu2fcfg. A bare
# mktemp is therefore a test failure; only the sudo stub below may invoke the
# real command, and it does so with an absolute scratch template.
cat >"$stub_bin/mktemp" <<'SH'
#!/bin/bash

printf 'mktemp' >>"$TEST_BARE_MKTEMP"
printf '\t%s' "$@" >>"$TEST_BARE_MKTEMP"
printf '\n' >>"$TEST_BARE_MKTEMP"
exit 98
SH

# Execute only the setup's expected bare-sudo protocol. The production mktemp
# template is logged exactly, but its root-created sibling is represented by a
# unique regular file inside the scratch directory. The whitelisted operations
# map every write into that directory; arbitrary direct commands are outside
# this harness.
cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

set -euo pipefail

reject() {
  printf 'refusing unexpected sudo invocation:' >&2
  printf ' %q' "$@" >&2
  printf '\n' >&2
  exit 97
}

if [[ ${TEST_TMP:-} != /* || ${TEST_AUTHDIR:-} != "$TEST_TMP/etc-fido2" || ${TEST_AUTHFILE:-} != "$TEST_AUTHDIR/fido2" || ${TEST_STAGES:-} != "$TEST_TMP/stages.log" || ${TEST_LOG:-} != "$TEST_TMP/calls.log" || ! ${TEST_FAIL_CHMOD:-} =~ ^[01]$ || ! ${TEST_FAIL_MV:-} =~ ^[01]$ ]]; then
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

case "${1:-}" in
  install)
    if (( $# != 9 )) || [[ $2 != "-d" || $3 != "-m" || $4 != "755" || $5 != "-o" || $6 != "root" || $7 != "-g" || $8 != "root" || $9 != "$TEST_AUTHDIR" ]]; then
      reject "$@"
    fi

    if (( EUID == 0 )); then
      exec /usr/bin/install -d -m 755 -o root -g root "$TEST_AUTHDIR"
    else
      exec /usr/bin/install -d -m 755 "$TEST_AUTHDIR"
    fi
    ;;
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
  tee)
    if (( $# == 2 )) && recorded_stage "$2"; then
      exec /usr/bin/tee "$2"
    elif (( $# == 2 )) && [[ $2 == "/etc/pam.d/polkit-1" ]]; then
      /usr/bin/cat >/dev/null
    else
      reject "$@"
    fi
    ;;
  test)
    if (( $# != 3 )) || [[ $2 != "-s" ]] || ! recorded_stage "$3"; then
      reject "$@"
    fi
    /usr/bin/test -s "$3"
    ;;
  chmod)
    if (( $# != 3 )) || [[ $2 != "644" ]] || ! recorded_stage "$3"; then
      reject "$@"
    fi
    if [[ $TEST_FAIL_CHMOD == "1" ]]; then
      exit 73
    fi
    exec /usr/bin/chmod 644 "$3"
    ;;
  mv)
    if (( $# != 4 )) || [[ $2 != "-Tf" || $4 != "$TEST_AUTHFILE" ]] || ! recorded_stage "$3"; then
      reject "$@"
    fi
    if [[ $TEST_FAIL_MV == "1" ]]; then
      exit 74
    fi
    exec /usr/bin/mv -Tf -- "$3" "$TEST_AUTHFILE"
    ;;
  rm)
    if (( $# != 4 )) || [[ $2 != "-f" || $3 != "--" ]] || ! recorded_stage "$4"; then
      reject "$@"
    fi
    exec /usr/bin/rm -f -- "$4"
    ;;
  sed)
    if (( $# != 4 )) || [[ $2 != "-i" ]]; then
      reject "$@"
    fi

    if [[ $3 == "1i auth    sufficient pam_u2f.so cue authfile=/etc/fido2/fido2" && $4 == "/etc/pam.d/sudo" ]]; then
      exit 0
    elif [[ $3 == "1i auth      sufficient pam_u2f.so cue authfile=/etc/fido2/fido2" && $4 == "/etc/pam.d/polkit-1" ]]; then
      exit 0
    else
      reject "$@"
    fi
    ;;
  echo)
    if (( $# != 2 )) || [[ $2 != "FIDO2 authentication test successful" ]]; then
      reject "$@"
    fi
    ;;
  *)
    reject "$@"
    ;;
esac
SH

# The setup reads the authenticator's own CTAP options before it registers
# anything, so -I answers as whichever class of key the case under test stands
# in for. Pinning the device operand also proves the setup probes the key it
# discovered rather than a path of its own invention.
cat >"$stub_bin/fido2-token" <<'SH'
#!/bin/bash

set -euo pipefail

case "${1:-}" in
  -L)
    printf '%s\n' '/dev/hidraw0: vendor=0x1050, product=0x0407 (Yubico YubiKey)'
    ;;
  -I)
    [[ ${2:-} == "/dev/hidraw0" ]] || exit 94
    [[ $TEST_TOKEN_INFO_FAILS == "0" ]] || exit 1
    printf '%s\n' "$TEST_TOKEN_INFO"
    ;;
  *)
    exit 93
    ;;
esac
SH

cat >"$stub_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
SH

# Record what pamu2fcfg's stdout actually targets. The fixed implementation
# gives it a pipe to privileged tee; refusing a regular-file descriptor keeps a
# regression from writing credential bytes into a caller-owned named file.
cat >"$stub_bin/pamu2fcfg" <<'SH'
#!/bin/bash

set -euo pipefail

# printf runs its format once even with nothing to substitute, so an
# unconditional '\t%s' would log a phantom empty argument for the no-flag case
# and the assertion below would be reading the stub rather than the setup.
printf 'pamu2fcfg' >>"$TEST_PAMU_ARGS"
if (( $# > 0 )); then
  printf '\t%s' "$@" >>"$TEST_PAMU_ARGS"
fi
printf '\n' >>"$TEST_PAMU_ARGS"

target=$(readlink /proc/self/fd/1)
printf '%s\n' "$target" >>"$TEST_PAMU_TARGETS"
[[ $target == pipe:* ]] || exit 96

case "$TEST_PAMU_MODE" in
  success)
    printf '%s\n' "$TEST_CREDENTIAL"
    ;;
  fail)
    printf '%s\n' "$TEST_CREDENTIAL"
    exit 23
    ;;
  empty)
    exit 0
    ;;
  *)
    exit 95
    ;;
esac
SH

chmod +x "$stub_bin/mktemp" "$stub_bin/sudo" "$stub_bin/fido2-token" \
  "$stub_bin/omarchy-pkg-add" "$stub_bin/pamu2fcfg"

reset_run() {
  : >"$calls"
  : >"$stages"
  : >"$pamu_targets"
  : >"$pamu_args"
  : >"$bare_mktemp"
  : >"$output"
  token_info=$default_token_info
  token_info_fails=0
  rm -rf "$authdir"
}

invoke_setup() {
  local pamu_mode="${1:-success}"
  local fail_chmod="${2:-0}"
  local fail_mv="${3:-0}"
  local mktemp_mode="${4:-normal}"

  TEST_AUTHDIR="$authdir" TEST_AUTHFILE="$authfile" TEST_BARE_MKTEMP="$bare_mktemp" \
    TEST_CREDENTIAL="$credential" TEST_FAIL_CHMOD="$fail_chmod" TEST_FAIL_MV="$fail_mv" \
    TEST_LOG="$calls" TEST_MKTEMP_MODE="$mktemp_mode" TEST_PAMU_MODE="$pamu_mode" \
    TEST_PAMU_ARGS="$pamu_args" TEST_PAMU_TARGETS="$pamu_targets" TEST_STAGES="$stages" \
    TEST_TMP="$test_tmp" TEST_TOKEN_INFO="$token_info" \
    TEST_TOKEN_INFO_FAILS="$token_info_fails" \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    bash "$setup_copy" </dev/null >"$output"
}

run_setup() {
  invoke_setup "${1:-success}" ||
    fail "FIDO2 setup registers a device that answers fido2-token" "sudo calls:
$(cat "$calls")"
}

safe_fixture_stage_path() {
  local candidate=$1
  local prefix="$authfile.new."
  local suffix

  [[ $candidate == "$prefix"* ]] || return 1
  suffix=${candidate#"$prefix"}
  [[ $suffix =~ ^[[:alnum:]]{6}$ ]]
}

single_stage() {
  local count

  count=$(wc -l <"$stages")
  (( count == 1 )) || fail "setup creates exactly one privileged stage" "got $count stages"
  head -n 1 "$stages"
}

assert_pipe_target() {
  local count target

  count=$(wc -l <"$pamu_targets")
  (( count == 1 )) || fail "setup invokes pamu2fcfg exactly once" "got $count invocations"
  target=$(head -n 1 "$pamu_targets")
  [[ $target == pipe:* ]] ||
    fail "pamu2fcfg writes only to a pipe, never a caller-owned named file" "got: $target"
}

assert_failed_stage_cleanup() {
  local stage_path

  stage_path=$(single_stage)
  safe_fixture_stage_path "$stage_path" ||
    fail "the failed setup stage is a unique scratch sibling" "got: $stage_path"
  grep -Fxq $'sudo\trm\t-f\t--\t'"$stage_path" "$calls" ||
    fail "failed setup removes its exact privileged stage" "$(cat "$calls")"
  [[ ! -e $stage_path && ! -L $stage_path ]] ||
    fail "the failed setup stage is gone" "left behind: $stage_path"
  [[ ! -e $authfile ]] || fail "failed setup never publishes a credential"
}

# Each branch below is a fixture rather than whatever the host happens to have
# at /etc/fido2, so all of them run on every machine and the staging assertions
# that follow are reached even on one that already uses FIDO2.
reset_run
mkdir -p "$authdir"
printf '%s\n' "$credential" >"$authfile"
run_setup
[[ ! -s $stages && ! -s $pamu_targets ]] ||
  fail "FIDO2 setup stages nothing when a registration already exists"
! grep -Fq $'sudo\tmktemp\t' "$calls" ||
  fail "FIDO2 setup creates no stage over an existing registration" "$(cat "$calls")"
pass "FIDO2 setup leaves an existing registration alone"

reset_run
mkdir -p "$authdir"
ln -s /dev/null "$authfile"
invoke_setup >/dev/null 2>&1 &&
  fail "FIDO2 setup refuses a symlinked authfile"
[[ ! -s $stages && ! -s $pamu_targets ]] ||
  fail "FIDO2 setup stages nothing against a symlinked authfile"
[[ -L $authfile ]] || fail "FIDO2 setup leaves the symlinked authfile in place"
pass "FIDO2 setup refuses a symlinked authfile"

reset_run
mkdir -p "$authfile"
invoke_setup >/dev/null 2>&1 &&
  fail "FIDO2 setup refuses a directory where the authfile belongs"
[[ ! -s $stages && ! -s $pamu_targets ]] ||
  fail "FIDO2 setup stages nothing against a directory authfile"
pass "FIDO2 setup refuses a non-regular authfile"

# install -d follows a symlink at the directory and applies its mode and
# ownership to whatever it points at, so the credential would be staged and
# published inside the target and that directory reopened to root:root 755.
reset_run
mkdir -p "$test_tmp/elsewhere"
chmod 700 "$test_tmp/elsewhere"
ln -s "$test_tmp/elsewhere" "$authdir"
invoke_setup >/dev/null 2>&1 &&
  fail "FIDO2 setup refuses a symlinked FIDO2 directory"
[[ ! -s $stages && ! -s $pamu_targets ]] ||
  fail "FIDO2 setup stages nothing through a symlinked FIDO2 directory"
! grep -Fq $'sudo\tinstall\t' "$calls" ||
  fail "FIDO2 setup never runs install -d through a symlink" "$(cat "$calls")"
[[ $(stat -c %a "$test_tmp/elsewhere") == "700" ]] ||
  fail "FIDO2 setup leaves the symlink target's mode alone" "got: $(stat -c %a "$test_tmp/elsewhere")"
[[ ! -e $test_tmp/elsewhere/fido2 ]] ||
  fail "FIDO2 setup publishes nothing inside the symlink target"
pass "FIDO2 setup refuses a symlinked FIDO2 directory and leaves its target alone"

reset_run
run_setup
stage_path=$(single_stage)
safe_fixture_stage_path "$stage_path" ||
  fail "FIDO2 setup uses a unique sibling stage" "got: $stage_path"
assert_pipe_target

[[ ! -s $bare_mktemp ]] ||
  fail "FIDO2 setup never creates a caller-owned temporary file" "$(cat "$bare_mktemp")"
grep -Fxq $'sudo\tmktemp\t'"$authfile.new.XXXXXX" "$calls" ||
  fail "FIDO2 setup asks root to create a unique sibling stage" "$(cat "$calls")"
grep -Fxq $'sudo\ttee\t'"$stage_path" "$calls" ||
  fail "pamu2fcfg is piped into the exact privileged stage" "$(cat "$calls")"
grep -Fxq $'sudo\tchmod\t644\t'"$stage_path" "$calls" ||
  fail "FIDO2 setup makes the completed authfile PAM-readable" "$(cat "$calls")"
grep -Fxq $'sudo\tmv\t-Tf\t'"$stage_path"$'\t'"$authfile" "$calls" ||
  fail "FIDO2 setup atomically publishes the exact privileged stage" "$(cat "$calls")"
! grep -Fq $'sudo\trm\t' "$calls" ||
  fail "successful setup leaves its cleanup trap inert" "$(cat "$calls")"

[[ ! -e $stage_path && ! -L $stage_path ]] ||
  fail "the privileged stage path is gone after publication" "left behind: $stage_path"
[[ -f $authfile && $(<"$authfile") == "$credential" ]] ||
  fail "the published authfile contains the generated credential"
[[ $(stat -c %a "$authfile") == "644" ]] ||
  fail "the published authfile is mode 644" "got: $(stat -c %a "$authfile")"
pass "FIDO2 setup pipes the credential into a unique root-created stage and publishes it atomically"

# A chmod failure happens after a complete credential has been written but
# before publication. It must abort the setup and leave the EXIT trap armed.
reset_run
if invoke_setup success 1 >/dev/null 2>&1; then
  fail "a failed chmod propagates out of FIDO2 setup"
fi
failed_stage=$(single_stage)
assert_pipe_target
grep -Fxq $'sudo\tchmod\t644\t'"$failed_stage" "$calls" ||
  fail "the injected chmod failure targets the exact privileged stage" "$(cat "$calls")"
! grep -Fq $'sudo\tmv\t' "$calls" ||
  fail "a stage whose chmod failed is never published" "$(cat "$calls")"
assert_failed_stage_cleanup
pass "FIDO2 setup propagates chmod failure and cleans its privileged stage"

# A failed atomic rename has the same cleanup obligation. The completed stage
# must not survive beside the live authfile when publication fails.
reset_run
if invoke_setup success 0 1 >/dev/null 2>&1; then
  fail "a failed mv propagates out of FIDO2 setup"
fi
failed_stage=$(single_stage)
assert_pipe_target
grep -Fxq $'sudo\tchmod\t644\t'"$failed_stage" "$calls" ||
  fail "the mv-failure fixture reaches a completed mode-644 stage" "$(cat "$calls")"
grep -Fxq $'sudo\tmv\t-Tf\t'"$failed_stage"$'\t'"$authfile" "$calls" ||
  fail "the injected mv failure targets the exact privileged stage" "$(cat "$calls")"
assert_failed_stage_cleanup
pass "FIDO2 setup propagates mv failure and cleans its privileged stage"

# Emit a valid credential and then fail. Without pipefail, tee's success masks
# pamu2fcfg's status and the nonempty file would be published.
reset_run
if invoke_setup fail >/dev/null 2>&1; then
  fail "a failing pamu2fcfg pipeline fails setup"
fi
assert_pipe_target
assert_failed_stage_cleanup
! grep -Fq $'sudo\tchmod\t' "$calls" ||
  fail "a failed pamu2fcfg result is never prepared for publication" "$(cat "$calls")"
! grep -Fq $'sudo\tmv\t' "$calls" ||
  fail "a failed pamu2fcfg result is never published" "$(cat "$calls")"
pass "FIDO2 setup propagates pamu2fcfg failure and cleans its privileged stage"

# A successful pipeline can still produce no credential. Reject that before
# chmod or rename, and clean the exact stage just as on command failure.
reset_run
if invoke_setup empty >/dev/null 2>&1; then
  fail "an empty pamu2fcfg result fails setup"
fi
assert_pipe_target
assert_failed_stage_cleanup
! grep -Fq $'sudo\tchmod\t' "$calls" ||
  fail "an empty pamu2fcfg result is never prepared for publication" "$(cat "$calls")"
! grep -Fq $'sudo\tmv\t' "$calls" ||
  fail "an empty pamu2fcfg result is never published" "$(cat "$calls")"
pass "FIDO2 setup rejects an empty credential and cleans its privileged stage"

# mktemp's output is an operand for a privileged tee, chmod, mv and rm. Take
# only the name this script asked for: a stage path outside that shape must stop
# the setup before any of them runs, exactly as the migration does.
reset_run
invoke_setup success 0 0 malformed >/dev/null 2>&1 &&
  fail "a malformed mktemp result fails setup"
! grep -Fq $'sudo\ttee\t' "$calls" ||
  fail "no credential is written to a malformed stage path" "$(cat "$calls")"
! grep -Fq $'sudo\tchmod\t' "$calls" ||
  fail "a malformed stage path never reaches a privileged chmod" "$(cat "$calls")"
! grep -Fq $'sudo\tmv\t' "$calls" ||
  fail "a malformed stage path is never published" "$(cat "$calls")"
! grep -Fq $'sudo\trm\t' "$calls" ||
  fail "a malformed stage path never reaches a privileged rm" "$(cat "$calls")"
[[ ! -e $authfile ]] || fail "a malformed stage publishes no authfile"
pass "FIDO2 setup rejects malformed mktemp output before any privileged write"

reset_run
invoke_setup success 0 0 nonregular >/dev/null 2>&1 &&
  fail "a nonregular mktemp result fails setup"
! grep -Fq $'sudo\ttee\t' "$calls" ||
  fail "no credential is written into a nonregular stage" "$(cat "$calls")"
! grep -Fq $'sudo\tchmod\t' "$calls" ||
  fail "a nonregular stage never reaches a privileged chmod" "$(cat "$calls")"
! grep -Fq $'sudo\tmv\t' "$calls" ||
  fail "a nonregular stage is never published" "$(cat "$calls")"
[[ ! -e $authfile ]] || fail "a nonregular stage publishes no authfile"
pass "FIDO2 setup rejects nonregular mktemp output before any privileged write"

# The authenticator decides the credential's flags, not this script. A key that
# enforces alwaysUv rejects every assertion that does not carry user
# verification, so a presence-only credential can never authenticate with it and
# setup reports a success that sudo then falls through. A key that does not
# enforce it is registered exactly as it was before, PIN or no PIN: what is
# recorded here is a requirement the key states, never a policy added on top.
assert_flags_for() {
  local description=$1 options=$2 expected=$3
  local logged

  reset_run
  token_info=$options
  run_setup

  logged=$(cat "$pamu_args")
  [[ $logged == "$expected" ]] ||
    fail "$description" "pamu2fcfg was invoked as: $logged"
  [[ -f $authfile && $(<"$authfile") == "$credential" ]] ||
    fail "$description" "no credential was published"
  pass "$description"
}

assert_flags_for "a key that always requires verification records its PIN" \
  'options: rk, up, noplat, alwaysUv, credMgmt, clientPin, pinUvAuthToken' \
  $'pamu2fcfg\t-N'

assert_flags_for "a key with built-in verification records that rather than its PIN" \
  'options: rk, up, uv, alwaysUv, clientPin, bioEnroll' \
  $'pamu2fcfg\t-V'

# nouv is the option present and false: built-in verification the key supports
# but nobody has configured. Reading it as configured would record -V and leave
# the credential unusable for the same reason as before.
assert_flags_for "an alwaysUv key with unconfigured built-in verification falls back to its PIN" \
  'options: rk, up, nouv, alwaysUv, clientPin' \
  $'pamu2fcfg\t-N'

assert_flags_for "a PIN-capable key that does not require verification is registered as before" \
  'options: rk, up, noplat, clientPin, pinUvAuthToken' \
  'pamu2fcfg'

assert_flags_for "a key with built-in verification but no alwaysUv is registered as before" \
  'options: rk, up, uv, clientPin, bioEnroll' \
  'pamu2fcfg'

assert_flags_for "a U2F-only key that reports no options at all is registered as before" \
  '/dev/hidraw0: vendor=0x1050, product=0x0407 (Yubico YubiKey)' \
  'pamu2fcfg'

# alwaysUv with neither a PIN nor configured built-in verification cannot
# produce a credential that authenticates. Say so instead of registering one,
# and say it before the first sudo: a key that cannot be set up is not worth a
# password prompt.
reset_run
token_info='options: rk, up, alwaysUv, noclientPin'
invoke_setup >/dev/null 2>&1 &&
  fail "FIDO2 setup refuses a key requiring verification it cannot perform"
[[ ! -s $stages && ! -s $pamu_targets && ! -s $pamu_args ]] ||
  fail "FIDO2 setup stages nothing for a key it cannot register"
[[ ! -e $authfile ]] ||
  fail "FIDO2 setup publishes nothing for a key it cannot register"
[[ ! -s $calls ]] ||
  fail "FIDO2 setup refuses an unregisterable key before it escalates" "$(cat "$calls")"
pass "FIDO2 setup refuses an alwaysUv key with no verification configured, before escalating"

# fido2-token -I failing aborted the setup through set -e, printing nothing at
# all: the terminal closed on a successful-looking run that had registered
# nothing. Assert the explanation, not just the exit status.
reset_run
token_info_fails=1
invoke_setup >/dev/null 2>&1 &&
  fail "FIDO2 setup fails when it cannot read the key's capabilities"
grep -Fq "Couldn't read the FIDO2 key's capabilities" "$output" ||
  fail "FIDO2 setup says why it gave up on a key it cannot read" "$(cat "$output")"
[[ ! -s $stages && ! -s $pamu_args ]] ||
  fail "FIDO2 setup stages nothing for a key it cannot read"
[[ ! -e $authfile ]] || fail "FIDO2 setup publishes nothing for a key it cannot read"
[[ ! -s $calls ]] ||
  fail "FIDO2 setup gives up on an unreadable key before it escalates" "$(cat "$calls")"
pass "FIDO2 setup reports why it bailed when the key cannot be read"
