#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

setup="$ROOT/bin/omarchy-setup-security-fido2"

test_tmp=$(mktemp -d)
stub_bin="$test_tmp/bin"
stage_dir="$test_tmp/stages"
stages="$test_tmp/stages.log"
calls="$test_tmp/calls.log"
pamu_targets="$test_tmp/pamu-targets.log"
bare_mktemp="$test_tmp/bare-mktemp.log"
published="$test_tmp/published"
credential="tester:credential-handle,public-key,es256,+presence"
authfile=/etc/fido2/fido2
mkdir -p "$stub_bin" "$stage_dir"

cleanup() {
  rm -rf "$test_tmp"
  return 0
}
trap cleanup EXIT

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

if [[ ${TEST_TMP:-} != /* || ${TEST_STAGE_DIR:-} != "$TEST_TMP/stages" || ${TEST_STAGES:-} != "$TEST_TMP/stages.log" || ${TEST_LOG:-} != "$TEST_TMP/calls.log" || ${TEST_PUBLISHED:-} != "$TEST_TMP/published" || ${TEST_AUTHFILE:-} != "/etc/fido2/fido2" || ! ${TEST_FAIL_CHMOD:-} =~ ^[01]$ || ! ${TEST_FAIL_MV:-} =~ ^[01]$ ]]; then
  reject "$@"
fi

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"

safe_stage_path() {
  local candidate=$1
  local prefix="$TEST_STAGE_DIR/fido2.new."
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
    if (( $# != 9 )) || [[ $2 != "-d" || $3 != "-m" || $4 != "755" || $5 != "-o" || $6 != "root" || $7 != "-g" || $8 != "root" || $9 != "/etc/fido2" ]]; then
      reject "$@"
    fi
    ;;
  mktemp)
    if (( $# != 2 )) || [[ $2 != "$TEST_AUTHFILE.new.XXXXXX" ]]; then
      reject "$@"
    fi

    stage=$(/usr/bin/mktemp -- "$TEST_STAGE_DIR/fido2.new.XXXXXX")
    if ! safe_stage_path "$stage" || [[ ! -f $stage || -L $stage ]]; then
      reject "$@"
    fi

    printf '%s\n' "$stage" >>"$TEST_STAGES"
    printf '%s\n' "$stage"
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
    exec /usr/bin/mv -Tf -- "$3" "$TEST_PUBLISHED"
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

cat >"$stub_bin/fido2-token" <<'SH'
#!/bin/bash

echo '/dev/hidraw0: vendor=0x1050, product=0x0407 (Yubico YubiKey)'
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
  : >"$bare_mktemp"
  rm -f "$published"
}

invoke_setup() {
  local pamu_mode="${1:-success}"
  local fail_chmod="${2:-0}"
  local fail_mv="${3:-0}"

  TEST_AUTHFILE="$authfile" TEST_BARE_MKTEMP="$bare_mktemp" TEST_CREDENTIAL="$credential" \
    TEST_FAIL_CHMOD="$fail_chmod" TEST_FAIL_MV="$fail_mv" TEST_LOG="$calls" \
    TEST_PAMU_MODE="$pamu_mode" TEST_PAMU_TARGETS="$pamu_targets" TEST_PUBLISHED="$published" \
    TEST_STAGE_DIR="$stage_dir" TEST_STAGES="$stages" TEST_TMP="$test_tmp" \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    bash "$setup" </dev/null >/dev/null
}

run_setup() {
  invoke_setup "${1:-success}" ||
    fail "FIDO2 setup registers a device that answers fido2-token" "sudo calls:
$(cat "$calls")"
}

safe_fixture_stage_path() {
  local candidate=$1
  local prefix="$stage_dir/fido2.new."
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
  [[ ! -e $published ]] || fail "failed setup never publishes a credential"
}

# The registration block is guarded on the host's own /etc/fido2/fido2, and no
# stub hides a file at an absolute path from it. Preserve coverage of the branch
# the host actually makes reachable instead of letting a no-op pass the staging
# assertions below.
reset_run
if [[ -f $authfile && ! -L $authfile ]]; then
  run_setup

  [[ ! -s $stages && ! -s $pamu_targets ]] ||
    fail "FIDO2 setup stages nothing when a registration already exists"
  ! grep -Fq $'sudo\tmktemp\t' "$calls" ||
    fail "FIDO2 setup creates no stage over an existing registration" "$(cat "$calls")"

  pass "FIDO2 setup leaves an existing registration alone; skipping the staging checks"
  exit 0
elif [[ -e $authfile || -L $authfile ]]; then
  invoke_setup >/dev/null 2>&1 &&
    fail "FIDO2 setup refuses a non-regular authfile" "it exited 0 against $(ls -ld "$authfile")"

  [[ ! -s $stages && ! -s $pamu_targets ]] ||
    fail "FIDO2 setup stages nothing against a non-regular authfile"

  pass "FIDO2 setup refuses a non-regular authfile; skipping the staging checks"
  exit 0
fi

run_setup
stage_path=$(single_stage)
safe_fixture_stage_path "$stage_path" ||
  fail "FIDO2 setup uses a unique sibling stage" "got: $stage_path"
assert_pipe_target

[[ ! -s $bare_mktemp ]] ||
  fail "FIDO2 setup never creates a caller-owned temporary file" "$(cat "$bare_mktemp")"
grep -Fxq $'sudo\tmktemp\t/etc/fido2/fido2.new.XXXXXX' "$calls" ||
  fail "FIDO2 setup asks root to create a unique sibling stage" "$(cat "$calls")"
grep -Fxq $'sudo\ttee\t'"$stage_path" "$calls" ||
  fail "pamu2fcfg is piped into the exact privileged stage" "$(cat "$calls")"
grep -Fxq $'sudo\tchmod\t644\t'"$stage_path" "$calls" ||
  fail "FIDO2 setup makes the completed authfile PAM-readable" "$(cat "$calls")"
grep -Fxq $'sudo\tmv\t-Tf\t'"$stage_path"$'\t/etc/fido2/fido2' "$calls" ||
  fail "FIDO2 setup atomically publishes the exact privileged stage" "$(cat "$calls")"
! grep -Fq $'sudo\trm\t' "$calls" ||
  fail "successful setup leaves its cleanup trap inert" "$(cat "$calls")"

[[ ! -e $stage_path && ! -L $stage_path ]] ||
  fail "the privileged stage path is gone after publication" "left behind: $stage_path"
[[ -f $published && $(<"$published") == "$credential" ]] ||
  fail "the published authfile contains the generated credential"
[[ $(stat -c %a "$published") == "644" ]] ||
  fail "the published authfile is mode 644" "got: $(stat -c %a "$published")"
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
grep -Fxq $'sudo\tmv\t-Tf\t'"$failed_stage"$'\t/etc/fido2/fido2' "$calls" ||
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
