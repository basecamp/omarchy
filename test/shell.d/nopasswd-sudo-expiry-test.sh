#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

command_path="$ROOT/bin/omarchy-sudo-passwordless"
security_library_path="$ROOT/bin/omarchy-security-functions"
tmpfiles_path="$ROOT/etc/tmpfiles.d/omarchy-nopasswd-sudo.conf"
migration_path="$ROOT/migrations/1788163635.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

function_prefix() {
  printf 'source %q\n' "$security_library_path"
  awk '/^source .*omarchy-security-functions/ { next } /^case "\$\{1:-\}" in$/ { exit } { print }' "$command_path"
}

# Exercise the validation code itself. Leading zeroes remain numeric, but zero,
# negatives, oversized grants, and shell syntax are rejected.
(
  source <(function_prefix)
  for minutes in 1 15 1440 00015; do
    valid_minutes "$minutes" || fail "passwordless sudo accepts bounded duration $minutes"
  done
  for minutes in 0 1441 -1 1m '1;id' ''; do
    ! valid_minutes "$minutes" || fail "passwordless sudo rejects invalid duration '$minutes'"
  done
)
pass "passwordless sudo validates a bounded positive duration"

# The public entry point uses the kernel-backed numeric identity; $USER is
# never interpolated into a privileged filename or sudoers rule.
grep -F 'uid=$(/usr/bin/id -u)' "$command_path" >/dev/null ||
  fail "passwordless sudo derives the caller from id -u"
! grep -Eq '\$\{?USER\}?' "$command_path" ||
  fail "passwordless sudo does not trust USER for privileged policy"
grep -F '[[ ${SUDO_UID:-} =~ ^[0-9]+$ ]]' "$command_path" >/dev/null ||
  fail "passwordless sudo validates sudo provenance"
pass "passwordless sudo derives and validates trusted account identity"

# Status inspection and the confirmation UI are mixed-trust: a normal sudo
# status call would publish a timestamp that a hostile prompt helper could use
# even when the user declines the grant. Exercise the public flow with a sudo
# model that publishes a token only when -N is missing.
grep -Fxq '#!/bin/bash -p' "$command_path" ||
  fail "passwordless sudo no longer suppresses Bash startup injection"
grep -F '[[ ${argv[1]:-} == -p ]]' "$security_library_path" >/dev/null ||
  fail "passwordless sudo accepts a decoy post-script -p"

public_sudo_stub="$test_tmp/public-sudo"
public_gum_stub="$test_tmp/public-gum"
public_token="$test_tmp/public-token"
public_exploit="$test_tmp/public-exploit"
cat >"$public_sudo_stub" <<'STUB'
#!/bin/bash
if [[ ${1:-} == -h ]]; then
  echo 'usage: sudo [-ABbEHkNnPS] command'
  exit 0
fi
if [[ ${1:-} == -k ]]; then
  rm -f -- "$TEST_PUBLIC_TOKEN"
  exit 0
fi
no_update=0
if [[ ${1:-} == -N ]]; then no_update=1; shift; fi
[[ ${1:-} != -- ]] || shift
((no_update)) || : >"$TEST_PUBLIC_TOKEN"
case "${2:-}" in
  __status) exit 1 ;;
  __enable|__disable) exit 0 ;;
  *) exit 2 ;;
esac
STUB
cat >"$public_gum_stub" <<'STUB'
#!/bin/bash
[[ ! -e $TEST_PUBLIC_TOKEN ]] || : >"$TEST_PUBLIC_EXPLOIT"
exit 1
STUB
chmod 0755 "$public_sudo_stub" "$public_gum_stub"
public_flow="$test_tmp/passwordless-public-flow"
/usr/bin/cp "$security_library_path" "$test_tmp/omarchy-security-functions"
/usr/bin/sed \
  -e "s#/usr/bin/sudo#$public_sudo_stub#g" \
  -e "s#/usr/bin/gum#$public_gum_stub#g" \
  "$command_path" >"$public_flow"
chmod 0755 "$public_flow"
TEST_PUBLIC_TOKEN="$public_token" TEST_PUBLIC_EXPLOIT="$public_exploit" \
  /usr/bin/bash -p "$public_flow" 15 >/dev/null
[[ ! -e $public_token && ! -e $public_exploit ]] ||
  fail "passwordless confirmation inherited a reusable status credential"

startup_env="$test_tmp/passwordless-bash-env"
startup_marker="$test_tmp/passwordless-bash-env-ran"
cat >"$startup_env" <<'STUB'
: >"$TEST_STARTUP_MARKER"
set -o privileged
unset BASH_ENV
STUB
if BASH_ENV="$startup_env" TEST_STARTUP_MARKER="$startup_marker" \
  /usr/bin/bash "$public_flow" -p >/dev/null 2>&1; then
  fail "passwordless sudo accepted an unsafe interpreter with a decoy -p"
fi
[[ -e $startup_marker && ! -e $public_token && ! -e $public_exploit ]] ||
  fail "unsafe passwordless startup reached its sudo workflow"
pass "passwordless confirmation uses a cold command-scoped credential boundary"

# Source a path-rewritten copy so the real cleanup implementation can be
# exercised without touching /etc. Exact generated numeric rules are removed
# even after account deletion or a crash before state publication. Anything an
# administrator changed, and every symlink, is preserved.
fake_sudoers="$test_tmp/sudoers.d"
mkdir "$fake_sudoers"
rewritten="$test_tmp/passwordless-lib.sh"
function_prefix | sed "s#/etc/sudoers.d#$fake_sudoers#g" >"$rewritten"
(
  source "$rewritten"
  printf 'deleteduser ALL=(ALL) NOPASSWD: ALL\n' >"$fake_sudoers/99-omarchy-nopasswd-424242"
  printf 'admin ALL=(ALL) NOPASSWD: /usr/bin/pacman\n' >"$fake_sudoers/99-omarchy-nopasswd-424243"
  ln -s "$fake_sudoers/99-omarchy-nopasswd-424243" "$fake_sudoers/99-omarchy-nopasswd-424244"
  remove_known_legacy_rules
)
[[ ! -e $fake_sudoers/99-omarchy-nopasswd-424242 ]] ||
  fail "boot cleanup removes a state-less numeric orphan"
[[ -f $fake_sudoers/99-omarchy-nopasswd-424243 ]] ||
  fail "boot cleanup preserves administrator-authored policy"
[[ -L $fake_sudoers/99-omarchy-nopasswd-424244 ]] ||
  fail "boot cleanup refuses sudoers symlinks"
pass "boot cleanup removes crash/deleted-account orphans conservatively"

# A boot gate must not report success when deletion itself fails. Exercise the
# real cleanup and post-cleanup verification with a deterministic failing rm.
rm_failure_dir="$test_tmp/rm-failure-sudoers"
mkdir "$rm_failure_dir"
printf 'deleteduser ALL=(ALL) NOPASSWD: ALL\n' >"$rm_failure_dir/99-omarchy-nopasswd-424245"
failing_rm="$test_tmp/failing-rm"
cat >"$failing_rm" <<'FAILING_RM'
#!/bin/bash
exit 1
FAILING_RM
chmod +x "$failing_rm"
rm_failure_lib="$test_tmp/rm-failure-lib.sh"
function_prefix |
  sed -e "s#/etc/sudoers.d#$rm_failure_dir#g" \
    -e "s#/var/lib/omarchy/sudo-passwordless#$test_tmp/empty-state#g" \
    -e "s#/usr/bin/rm#$failing_rm#g" >"$rm_failure_lib"
mkdir "$test_tmp/empty-state"
(
  source "$rm_failure_lib"
  ! cleanup_all_locked
) || fail "boot cleanup fails when an Omarchy rule cannot be removed"
[[ -f $rm_failure_dir/99-omarchy-nopasswd-424245 ]] ||
  fail "rm-failure fixture remains available for verification"
pass "boot cleanup fails closed when policy deletion fails"

# Reproduce the migration's real sudo provenance: sudo sets SUDO_UID. Rewrite
# only the read-only EUID probe so this unprivileged test can exercise the root
# dispatcher, then assert that cleanup (which can only revoke privilege) runs.
dispatch_lib="$test_tmp/dispatch-lib.sh"
function_prefix | sed 's/((EUID == 0))/((TEST_EUID == 0))/g' >"$dispatch_lib"
(
  source "$dispatch_lib"
  called=""
  cleanup_all_locked() { called=cleanup; }
  with_root_lock() { "$@"; }
  TEST_EUID=0 SUDO_UID=1000 root_dispatch __cleanup-all
  [[ $called == cleanup ]]
) || fail "migration cleanup dispatch accepts authenticated sudo provenance"
pass "migration can invoke fail-closed cleanup through sudo"

# A grant cannot be published until the static unit is verified/enabled, and a
# timer setup failure removes its pending state without calling publish_rule.
transaction_dir="$test_tmp/transaction"
mkdir "$transaction_dir"
transaction_lib="$test_tmp/transaction-lib.sh"
function_prefix | sed "s#/var/lib/omarchy/sudo-passwordless#$transaction_dir#g" >"$transaction_lib"
(
  source "$transaction_lib"
  ACCOUNT_NAME=audituser
  resolve_account() { ACCOUNT_NAME=audituser; ACCOUNT_UID=1000; }
  prepare_root_state() { :; }
  verify_boot_cleanup() { return 1; }
  publish_rule() { return 99; }
  ! enable_locked 1000 15
)
(
  source "$transaction_lib"
  ACCOUNT_NAME=audituser
  resolve_account() { ACCOUNT_NAME=audituser; ACCOUNT_UID=1000; }
  prepare_root_state() { :; }
  verify_boot_cleanup() { return 0; }
  read_state_timer() { return 1; }
  prepare_state_file() { local pending="$transaction_dir/pending"; : >"$pending"; printf %s "$pending"; }
  start_expiry_timer() { return 1; }
  publish_rule() { printf published >"$transaction_dir/published"; }
  cleanup_uid_locked() { : >"$transaction_dir/failed-timer-cleanup"; }
  ! enable_locked 1000 15
  [[ ! -e $transaction_dir/pending && ! -e $transaction_dir/published &&
    -e $transaction_dir/failed-timer-cleanup ]]
) || fail "passwordless sudo fails closed on prerequisite/timer failure"
pass "passwordless sudo publishes no rule after partial setup failure"

# Erik's predecessor fix revoked an already-active grant when an extension
# could not arm its replacement timer. Keep that fail-closed property while
# the new transaction deliberately leaves the old timer armed until the new
# one is verified.
replacement_state="$transaction_dir/1000.state"
replacement_rule="$transaction_dir/1000.rule"
replacement_stopped="$transaction_dir/old-timer-stopped"
old_timer=omarchy-nopasswd-expire-1000-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
printf 'UID=1000\nUSER=audituser\nEXPIRES=2000000000\nTIMER=%s\n' "$old_timer" >"$replacement_state"
printf 'audituser ALL=(ALL) NOPASSWD: ALL\n' >"$replacement_rule"
(
  source "$transaction_lib"
  resolve_account() { ACCOUNT_NAME=audituser; ACCOUNT_UID=1000; }
  prepare_root_state() { :; }
  verify_boot_cleanup() { return 0; }
  state_file() { printf '%s' "$replacement_state"; }
  rule_file() { printf '%s' "$replacement_rule"; }
  prepare_state_file() { local pending="$transaction_dir/replacement-pending"; : >"$pending"; printf %s "$pending"; }
  start_expiry_timer() { return 1; }
  stop_timer() { [[ $1 == "$old_timer" ]] && : >"$replacement_stopped"; }
  ! enable_locked 1000 30
  [[ ! -e $replacement_state && ! -e $replacement_rule && -e $replacement_stopped ]]
) || fail "passwordless sudo leaves an existing grant live after replacement timer failure"
pass "replacement timer failure revokes the existing grant"

# Expiry is a wall-clock promise, so the transient timer must carry the exact
# absolute epoch recorded in root state. A monotonic-only --on-active timer
# pauses during suspend and can otherwise extend a short grant by hours.
timer_args="$test_tmp/timer-args"
calendar_systemd_run="$test_tmp/calendar-systemd-run"
calendar_systemctl="$test_tmp/calendar-systemctl"
cat >"$calendar_systemd_run" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" >"$TEST_TIMER_ARGS"
STUB
cat >"$calendar_systemctl" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod 0755 "$calendar_systemd_run" "$calendar_systemctl"
calendar_lib="$test_tmp/calendar-lib.sh"
function_prefix |
  sed -e "s#/usr/bin/systemd-run#$calendar_systemd_run#g" \
    -e "s#/usr/bin/systemctl#$calendar_systemctl#g" >"$calendar_lib"
(
  source "$calendar_lib"
  TEST_TIMER_ARGS="$timer_args" start_expiry_timer 1000 2000000000 \
    omarchy-nopasswd-expire-1000-0123456789abcdef0123456789abcdef
) || fail "passwordless sudo cannot arm its absolute expiry timer"
grep -Fx -- '--on-calendar=@2000000000' "$timer_args" >/dev/null ||
  fail "passwordless sudo timer does not advance across suspend"
pass "passwordless sudo arms the recorded absolute wall-clock expiry"

# A resumed machine can briefly observe the timer as active before systemd
# dispatches its overdue service. Status must independently enforce EXPIRES and
# synchronously remove policy instead of trusting timer activity alone.
expired_state="$test_tmp/expired-state"
expired_sudoers="$test_tmp/expired-sudoers"
mkdir "$expired_state" "$expired_sudoers"
expired_timer=omarchy-nopasswd-expire-1000-0123456789abcdef0123456789abcdef
printf 'UID=1000\nUSER=audituser\nEXPIRES=1\nTIMER=%s\n' "$expired_timer" >"$expired_state/1000.state"
printf 'audituser ALL=(ALL) NOPASSWD: ALL\n' >"$expired_sudoers/99-omarchy-nopasswd-1000"
expired_lib="$test_tmp/expired-lib.sh"
function_prefix |
  sed -e "s#/var/lib/omarchy/sudo-passwordless#$expired_state#g" \
    -e "s#/etc/sudoers.d#$expired_sudoers#g" \
    -e "s#/usr/bin/systemctl#$calendar_systemctl#g" >"$expired_lib"
(
  source "$expired_lib"
  resolve_account() { ACCOUNT_NAME=audituser; ACCOUNT_UID=1000; }
  ! status_locked 1000
) || fail "passwordless sudo accepts expired root state while its timer is active"
[[ ! -e $expired_state/1000.state && ! -e $expired_sudoers/99-omarchy-nopasswd-1000 ]] ||
  fail "passwordless sudo does not synchronously revoke expired state"
pass "passwordless sudo enforces wall-clock expiry independently of timer dispatch"

# If the transient timer fires between its first active check and publication,
# the just-created rule must be synchronously revoked instead of surviving to
# reboot. Model that narrow transition with the real enable transaction.
inactive_systemctl="$test_tmp/inactive-systemctl"
cat >"$inactive_systemctl" <<'STUB'
#!/bin/bash
exit 1
STUB
chmod 0755 "$inactive_systemctl"
post_publish_lib="$test_tmp/post-publish-lib.sh"
sed "s#/usr/bin/systemctl#$inactive_systemctl#g" "$transaction_lib" >"$post_publish_lib"
(
  source "$post_publish_lib"
  resolve_account() { ACCOUNT_NAME=audituser; ACCOUNT_UID=1000; }
  prepare_root_state() { :; }
  verify_boot_cleanup() { return 0; }
  read_state_timer() { return 1; }
  prepare_state_file() { local pending="$transaction_dir/pending-after-arm"; : >"$pending"; printf %s "$pending"; }
  start_expiry_timer() { return 0; }
  publish_rule() { : >"$transaction_dir/published-after-arm"; }
  cleanup_uid_locked() { rm -f "$transaction_dir/published-after-arm"; : >"$transaction_dir/revoked-after-arm"; }
  ! enable_locked 1000 15
  [[ ! -e $transaction_dir/published-after-arm && -e $transaction_dir/revoked-after-arm ]]
) || fail "passwordless sudo leaves a grant when its armed timer expires before publication completes"
pass "timer expiry during publication revokes the grant synchronously"

# Follow the maintainer's package-owned tmpfiles design: one boot-only rule
# owns this filename namespace. A routine --remove leaves live grants alone;
# early boot removes them before a user can log in. The migration only revokes
# legacy runtime state and never writes static policy into /usr.
mapfile -t tmpfiles_rules < <(/usr/bin/grep -vE '^[[:space:]]*(#|$)' "$tmpfiles_path")
(( ${#tmpfiles_rules[@]} == 1 )) || fail "passwordless sudo ships one boot cleanup rule"
[[ ${tmpfiles_rules[0]} == 'r! /etc/sudoers.d/99-omarchy-nopasswd-*' ]] ||
  fail "passwordless sudo boot cleanup does not own the exact generated namespace"
fake_root="$test_tmp/tmpfiles-root"
sudoers_dir="$fake_root/etc/sudoers.d"
mkdir -p "$sudoers_dir"
for name in alice buildbot-2 424242; do
  : >"$sudoers_dir/99-omarchy-nopasswd-$name"
done
: >"$sudoers_dir/omarchy-dns"
/usr/bin/systemd-tmpfiles --root="$fake_root" --remove --inline "${tmpfiles_rules[0]}"
[[ -e $sudoers_dir/99-omarchy-nopasswd-alice ]] || fail "non-boot tmpfiles run shortened a live grant"
/usr/bin/systemd-tmpfiles --root="$fake_root" --remove --boot --inline "${tmpfiles_rules[0]}"
! find "$sudoers_dir" -name '99-omarchy-nopasswd-*' -print -quit | /usr/bin/grep -q . ||
  fail "boot cleanup left a generated passwordless grant"
[[ -e $sudoers_dir/omarchy-dns ]] || fail "boot cleanup removed an unrelated sudoers rule"
/usr/bin/grep -Fx 'sudo /usr/bin/omarchy-sudo-passwordless __cleanup-all' "$migration_path" >/dev/null
! /usr/bin/grep -q 'omarchy-sudo-passwordless-cleanup.service' "$migration_path" ||
  fail "migration retained a custom boot service instead of package-owned tmpfiles"
pass "package-owned boot cleanup is narrow, boot-only, and migration-safe"

# Removing the settings package also removes the tmpfiles rule. Its package
# lifecycle must therefore revoke the same owned namespace synchronously, while
# preserving every unrelated sudoers file.
pkgs_candidates=(
  "${OMARCHY_PKGS_PATH:-}"
  "$ROOT/../omarchy-pkgs"
  "$ROOT/../../omarchy-pkgs"
  "$HOME/Work/omarchy/omarchy-pkgs"
  "$HOME/Work/omacom/omarchy-pkgs"
)
pkgs_root=""
for candidate in "${pkgs_candidates[@]}"; do
  if [[ -n $candidate && -d $candidate/pkgbuilds/omarchy-settings ]]; then
    pkgs_root=$candidate
    break
  fi
done
[[ -n $pkgs_root ]] || fail "omarchy-pkgs checkout found for passwordless package-removal coverage"

for package_name in omarchy-settings omarchy-settings-dev; do
  install_script="$pkgs_root/pkgbuilds/$package_name/$package_name.install"
  transformed_install="$test_tmp/$package_name.install"
  removal_root="$test_tmp/$package_name-remove"
  removal_sudoers="$removal_root/etc/sudoers.d"
  mkdir -p "$removal_sudoers"
  : >"$removal_sudoers/99-omarchy-nopasswd-1000"
  : >"$removal_sudoers/99-omarchy-nopasswd-legacy-user"
  : >"$removal_sudoers/omarchy-dns"
  ln -s ../usr/share/omarchy/etc-overrides/os-release "$removal_root/etc/os-release"
  grep -Fq 'ln -s ../usr/share/omarchy/etc-overrides/os-release            /etc/os-release' "$install_script" ||
    fail "$package_name installation does not select package-owned OS metadata"
  sed "s#/etc/#$removal_root/etc/#g" "$install_script" >"$transformed_install"
  (
    source "$transformed_install"
    post_remove
  ) || fail "$package_name removal revokes active passwordless grants"
  ! find "$removal_sudoers" -name '99-omarchy-nopasswd-*' -print -quit | grep -q . ||
    fail "$package_name removal leaves a passwordless grant behind"
  [[ -e $removal_sudoers/omarchy-dns ]] ||
    fail "$package_name removal deletes an unrelated sudoers policy"
  [[ -L $removal_root/etc/os-release ]] &&
    [[ $(readlink "$removal_root/etc/os-release") == ../usr/lib/os-release ]] ||
    fail "$package_name removal does not restore the standard OS selector"

  ln -sfn ../administrator/os-release "$removal_root/etc/os-release"
  : >"$removal_sudoers/99-omarchy-nopasswd-1001"
  (
    source "$transformed_install"
    post_remove
  ) || fail "$package_name removal handles administrator OS selector state"
  [[ $(readlink "$removal_root/etc/os-release") == ../administrator/os-release ]] ||
    fail "$package_name removal overwrites an administrator OS selector"
  [[ ! -e $removal_sudoers/99-omarchy-nopasswd-1001 ]] ||
    fail "$package_name removal grant cleanup depends on OS selector state"
done
pass "settings package removal revokes grants and preserves package-selector ownership"

# Exercise the production flock wrapper under contention. mkdir is an atomic
# overlap detector; all workers must enter and leave the protected region.
lock_dir="$test_tmp/lock-runtime"
mkdir "$lock_dir"
lock_lib="$test_tmp/lock-lib.sh"
function_prefix |
  sed -e "s#/run/omarchy/sudo-passwordless#$lock_dir#g" \
    -e "s#/run/lock/omarchy-sudo-passwordless.lock#$test_tmp/passwordless.lock#g" \
    -e 's#/usr/bin/chown root:root "$LOCK_FILE"#/usr/bin/true#' >"$lock_lib"
worker="$test_tmp/worker.sh"
cat >"$worker" <<'WORKER'
#!/bin/bash
set -euo pipefail
source "$LOCK_LIB"
prepare_root_state() { :; }
critical() {
  mkdir "$LOCK_SENTINEL"
  sleep 0.03
  rmdir "$LOCK_SENTINEL"
  printf x >>"$LOCK_RESULTS"
}
with_root_lock critical
WORKER
chmod +x "$worker"
for _ in {1..8}; do
  LOCK_LIB="$lock_lib" LOCK_SENTINEL="$test_tmp/held" LOCK_RESULTS="$test_tmp/results" bash "$worker" &
done
wait
[[ $(wc -c <"$test_tmp/results") == 8 ]] || fail "concurrent passwordless operations serialize"
pass "passwordless sudo serializes concurrent operations"

# Same-boot expiry calls the fixed installed cleanup command, and cleanup
# removes policy before touching a timer so timer failures cannot extend it.
grep -F '"$INSTALLED_SELF" __expire "$uid"' "$command_path" >/dev/null
cleanup_body=$(awk '/^cleanup_uid_locked\(\) \{/ { in_body=1 } in_body { print } in_body && /^}/ { exit }' "$command_path")
rm_line=$(grep -n '/usr/bin/rm -f' <<<"$cleanup_body" | head -1 | cut -d: -f1)
stop_line=$(grep -n 'stop_timer' <<<"$cleanup_body" | tail -1 | cut -d: -f1)
((rm_line < stop_line)) || fail "expiry removes sudo policy before timer cleanup"
pass "same-boot expiration is fixed-target and fail closed"
